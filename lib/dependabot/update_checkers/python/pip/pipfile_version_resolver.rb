# frozen_string_literal: true

require "dependabot/file_parsers/python/pip"
require "dependabot/update_checkers/python/pip"
require "dependabot/utils/python/version"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip
        # This class does version resolution for Pipfiles. Its current approach
        # is somewhat crude:
        # - Unlock the dependency we're checking in the Pipfile
        # - Freeze all of the other dependencies in the Pipfile
        # - Run `pipenv lock` and see what the result is
        #
        # Unfortunately, Pipenv doesn't resolve how we'd expect - it appears to
        # just raise if the latest version can't be resolved. Knowing that is
        # still better than nothing, though.
        class PipfileVersionResolver
          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/

          attr_reader :dependency, :dependency_files, :credentials

          def initialize(dependency:, dependency_files:, credentials:)
            @dependency = dependency
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def latest_resolvable_version
            return @latest_resolvable_version if @resolution_already_attempted

            @resolution_already_attempted = true
            @latest_resolvable_version ||= fetch_latest_resolvable_version
          end

          private

          def fetch_latest_resolvable_version
            @latest_resolvable_version_string ||=
              SharedHelpers.in_a_temporary_directory do
                write_temporary_dependency_files

                # Shell out to Pipenv, which handles everything for us.
                # Whilst calling `lock` avoids doing an install as part of the
                # pipenv flow, an install is still done by pip-tools in order
                # to resolve the dependencies. That means this is slow.
                run_pipenv_command("pipenv lock")

                updated_lockfile = JSON.parse(File.read("Pipfile.lock"))
                updated_lockfile.dig(
                  dependency_lockfile_group,
                  dependency.name,
                  "version"
                ).gsub(/^==/, "")
              rescue SharedHelpers::HelperSubprocessFailed => error
                raise unless error.message.include?("could not be resolved")
              end
            return unless @latest_resolvable_version_string
            Utils::Python::Version.new(@latest_resolvable_version_string)
          end

          def write_temporary_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end

            # Workaround for Pipenv bug
            FileUtils.mkdir_p("python_package.egg-info")

            # Overwrite the pipfile with updated content
            File.write("Pipfile", pipfile_content)
          end

          def pipfile_content
            content = pipfile.content
            content = remove_python_requirement(content)
            content = freeze_other_dependencies(content)
            content = unlock_target_dependency(content)
            content = add_private_sources(content)
            content
          end

          def remove_python_requirement(pipfile_content)
            # TODO: It would be nice to handle this in Python, rather than here.
            # We should submit a patch to Pipenv to allow us to ignore the
            # required Python version there.
            pipfile_object = TomlRB.parse(pipfile_content)

            return pipfile_content unless pipfile_object["requires"]
            pipfile_object["requires"].delete("python_full_version")
            pipfile_object["requires"].delete("python_version")

            TomlRB.dump(pipfile_object)
          end

          def freeze_other_dependencies(pipfile_content)
            return pipfile_content unless lockfile
            pipfile_object = TomlRB.parse(pipfile_content)

            FileParsers::Python::Pip::DEPENDENCY_GROUP_KEYS.each do |keys|
              next unless pipfile_object[keys[:pipfile]]

              pipfile_object.fetch(keys[:pipfile]).each do |dep_name, _|
                next if dep_name == dependency.name
                next unless dependency_version(dep_name, keys[:lockfile])

                pipfile_object[keys[:pipfile]][dep_name] =
                  "==#{dependency_version(dep_name, keys[:lockfile])}"
              end
            end

            TomlRB.dump(pipfile_object)
          end

          def unlock_target_dependency(pipfile_content)
            pipfile_object = TomlRB.parse(pipfile_content)

            %w(packages dev-packages).each do |type|
              if pipfile_object.dig(type, dependency.name)
                pipfile_object[type][dependency.name] =
                  updated_version_requirement_string
              end
            end

            TomlRB.dump(pipfile_object)
          end

          def add_private_sources(pipfile_content)
            pipfile_object = TomlRB.parse(pipfile_content)

            original_sources = pipfile_object["source"].map(&:dup)
            env_sources = original_sources.
                          select { |h| h["url"].include?("${") }

            updated_sources = original_sources -
                              env_sources +
                              config_variable_sources

            pipfile_object["source"] = updated_sources

            TomlRB.dump(pipfile_object)
          end

          def updated_version_requirement_string
            return ">= #{dependency.version}" if dependency.version

            version_for_requirement =
              dependency.requirements.map { |r| r[:requirement] }.compact.
              reject { |req_string| req_string.start_with?("<") }.
              select { |req_string| req_string.match?(VERSION_REGEX) }.
              map { |req_string| req_string.match(VERSION_REGEX) }.
              select { |version| Gem::Version.correct?(version) }.
              max_by { |version| Gem::Version.new(version) }

            ">= #{version_for_requirement || 0}"
          end

          def dependency_version(dep_name, group)
            parsed_lockfile.
              dig(group, dep_name, "version")&.
              gsub(/^==/, "")
          end

          def dependency_lockfile_group
            dependency.requirements.first[:groups].first
          end

          def parsed_lockfile
            @parsed_lockfile ||= JSON.parse(lockfile.content)
          end

          def pipfile
            dependency_files.find { |f| f.name == "Pipfile" }
          end

          def lockfile
            dependency_files.find { |f| f.name == "Pipfile.lock" }
          end

          def run_pipenv_command(command)
            raw_response = nil
            IO.popen(command, err: %i(child out)) do |process|
              raw_response = process.read
            end

            # Raise an error with the output from the shell session if Pipenv
            # returns a non-zero status
            return if $CHILD_STATUS.success?
            raise SharedHelpers::HelperSubprocessFailed.new(
              raw_response,
              command
            )
          end

          def config_variable_sources
            @config_variable_sources ||=
              credentials.
              select { |cred| cred["index-url"] }.
              map { |cred| { "url" => cred["index-url"] } }
          end
        end
      end
    end
  end
end
