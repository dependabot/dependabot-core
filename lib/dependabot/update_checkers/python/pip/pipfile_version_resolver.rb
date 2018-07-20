# frozen_string_literal: true

require "excon"
require "toml-rb"

require "dependabot/file_parsers/python/pip"
require "dependabot/file_updaters/python/pip/pipfile_preparer"
require "dependabot/update_checkers/python/pip"
require "dependabot/shared_helpers"
require "dependabot/utils/python/version"
require "dependabot/errors"

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

          def initialize(dependency:, dependency_files:, credentials:,
                         unlock_requirement:, latest_allowable_version:)
            @dependency               = dependency
            @dependency_files         = dependency_files
            @credentials              = credentials
            @latest_allowable_version = latest_allowable_version
            @unlock_requirement       = unlock_requirement

            check_private_sources_are_reachable
          end

          def latest_resolvable_version
            return @latest_resolvable_version if @resolution_already_attempted

            @resolution_already_attempted = true
            @latest_resolvable_version ||= fetch_latest_resolvable_version
          end

          private

          attr_reader :latest_allowable_version

          def unlock_requirement?
            @unlock_requirement
          end

          def fetch_latest_resolvable_version
            @latest_resolvable_version_string ||=
              SharedHelpers.in_a_temporary_directory do
                write_temporary_dependency_files

                # Shell out to Pipenv, which handles everything for us.
                # Whilst calling `lock` avoids doing an install as part of the
                # pipenv flow, an install is still done by pip-tools in order
                # to resolve the dependencies. That means this is slow.
                run_pipenv_command("PIPENV_YES=true PIPENV_MAX_RETRIES=2 "\
                                   "pyenv exec pipenv lock")

                updated_lockfile = JSON.parse(File.read("Pipfile.lock"))
                updated_lockfile.dig(
                  dependency_lockfile_group,
                  dependency.name,
                  "version"
                ).gsub(/^==/, "")
              rescue SharedHelpers::HelperSubprocessFailed => error
                handle_pipenv_errors(error)
              end
            return unless @latest_resolvable_version_string
            Utils::Python::Version.new(@latest_resolvable_version_string)
          end

          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/PerceivedComplexity
          def handle_pipenv_errors(error)
            if error.message.include?("no version found at all") ||
               error.message.include?("Invalid specifier:")
              msg = clean_error_message(error.message)
              raise if msg.empty?
              raise DependencyFileNotResolvable, msg
            end

            if error.message.include?("Could not find a version") &&
               !original_requirements_resolvable?
              msg = clean_error_message(error.message)
              msg.gsub!(/\s+\(from .*$/, "")
              raise if msg.empty?
              raise DependencyFileNotResolvable, msg
            end

            if error.message.include?('Command "python setup.py egg_info') &&
               error.message.include?(dependency.name)
              # The latest version of the dependency we're updating is borked
              # (because it has an unevaluatable setup.py). Skip the update.
              return nil
            end

            raise unless error.message.include?("could not be resolved")
          end
          # rubocop:enable Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/PerceivedComplexity

          # Needed because Pipenv's resolver isn't perfect
          def original_requirements_resolvable?
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files(update_pipfile: false)

              run_pipenv_command("PIPENV_YES=true PIPENV_MAX_RETRIES=2 "\
                                   "pyenv exec pipenv lock")

              true
            rescue SharedHelpers::HelperSubprocessFailed => error
              return false if error.message.include?("Could not find a version")
              raise
            end
          end

          def clean_error_message(message)
            # Pipenv outputs a lot of things to STDERR, so we need to clean
            # up the error message
            msg_lines = message.lines
            msg = msg_lines.
                  take_while { |l| !l.start_with?("During handling of") }.
                  drop_while do |l|
                    !l.start_with?(
                      "Could not find",
                      "packaging.specifiers.InvalidSpecifier"
                    )
                  end.join.strip

            # We also need to redact any URLs, as they may include credentials
            msg.gsub(/http.*?(?=\s)/, "<redacted>")
          end

          def write_temporary_dependency_files(update_pipfile: true)
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end

            # Workaround for Pipenv bug
            FileUtils.mkdir_p("python_package.egg-info")

            # Overwrite the pipfile with updated content
            File.write("Pipfile", pipfile_content) if update_pipfile
          end

          def pipfile_content
            content = pipfile.content
            content = freeze_other_dependencies(content)
            content = unlock_target_dependency(content) if unlock_requirement?
            content = add_private_sources(content)
            content
          end

          def freeze_other_dependencies(pipfile_content)
            FileUpdaters::Python::Pip::PipfilePreparer.
              new(pipfile_content: pipfile_content).
              freeze_top_level_dependencies_except([dependency], lockfile)
          end

          def unlock_target_dependency(pipfile_content)
            pipfile_object = TomlRB.parse(pipfile_content)

            %w(packages dev-packages).each do |type|
              names = pipfile_object[type]&.keys || []
              pkg_name = names.find { |nm| normalise(nm) == dependency.name }
              next unless pkg_name

              if pipfile_object.dig(type, pkg_name).is_a?(Hash)
                pipfile_object[type][pkg_name]["version"] =
                  updated_version_requirement_string
              else
                pipfile_object[type][pkg_name] =
                  updated_version_requirement_string
              end
            end

            TomlRB.dump(pipfile_object)
          end

          def add_private_sources(pipfile_content)
            FileUpdaters::Python::Pip::PipfilePreparer.
              new(pipfile_content: pipfile_content).
              replace_sources(credentials)
          end

          def check_private_sources_are_reachable
            env_sources = pipfile_sources.select { |h| h["url"].include?("${") }

            check_env_sources_included_in_config_variables(env_sources)

            sources_to_check =
              pipfile_sources.reject { |h| h["url"].include?("${") } +
              config_variable_sources

            sources_to_check.
              map { |details| details["url"] }.
              reject { |url| MAIN_PYPI_INDEXES.include?(url) }.
              each do |url|
                sanitized_url = url.gsub(%r{(?<=//).*(?=@)}, "redacted")

                response = Excon.get(
                  url + dependency.name + "/",
                  idempotent: true,
                  **SharedHelpers.excon_defaults
                )

                if response.status == 401 || response.status == 403
                  raise PrivateSourceAuthenticationFailure, sanitized_url
                end
              rescue Excon::Error::Timeout, Excon::Error::Socket
                raise PrivateSourceTimedOut, sanitized_url
              end
          end

          def updated_version_requirement_string
            lower_bound_req = updated_version_req_lower_bound

            # Add the latest_allowable_version as an upper bound. This means
            # ignore conditions are considered when checking for the latest
            # resolvable version.
            #
            # NOTE: This isn't perfect. If v2.x is ignored and v3 is out but
            # unresolvable then the `latest_allowable_version` will be v3, and
            # we won't be ignoring v2.x releases like we should be.
            return lower_bound_req if latest_allowable_version.nil?
            unless Utils::Python::Version.correct?(latest_allowable_version)
              return lower_bound_req
            end

            lower_bound_req + ", <= #{latest_allowable_version}"
          end

          def updated_version_req_lower_bound
            if dependency.version
              ">= #{dependency.version}"
            else
              version_for_requirement =
                dependency.requirements.map { |r| r[:requirement] }.compact.
                reject { |req_string| req_string.start_with?("<") }.
                select { |req_string| req_string.match?(VERSION_REGEX) }.
                map { |req_string| req_string.match(VERSION_REGEX) }.
                select { |version| Gem::Version.correct?(version) }.
                max_by { |version| Gem::Version.new(version) }

              ">= #{version_for_requirement || 0}"
            end
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

          def check_env_sources_included_in_config_variables(env_sources)
            config_variable_source_urls =
              config_variable_sources.map { |s| s["url"] }

            env_sources.each do |source|
              url = source["url"]
              known_parts = url.split(/\$\{.*?\}/).reject(&:empty?).compact

              # If the whole URL is an environment variable we can't do a check
              next if known_parts.none?

              regex = known_parts.map { |p| Regexp.quote(p) }.join(".*?")
              next if config_variable_source_urls.any? { |s| s.match?(regex) }
              raise PrivateSourceAuthenticationFailure, url
            end
          end

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalise(name)
            name.downcase.tr("_", "-").tr(".", "-")
          end

          def config_variable_sources
            @config_variable_sources ||=
              credentials.
              select { |cred| cred["type"] == "python_index" }.
              map { |h| { "url" => h["index-url"].gsub(%r{/*$}, "") + "/" } }
          end

          def pipfile_sources
            @pipfile_sources ||=
              TomlRB.parse(pipfile.content).fetch("source", []).
              map { |h| h.dup.merge("url" => h["url"].gsub(%r{/*$}, "") + "/") }
          end
        end
      end
    end
  end
end
