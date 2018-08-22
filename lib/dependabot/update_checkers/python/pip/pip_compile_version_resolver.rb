# frozen_string_literal: true

require "dependabot/update_checkers/python/pip"
require "dependabot/file_updaters/python/pip/requirement_replacer"
require "dependabot/utils/python/version"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip
        # This class does version resolution for pip-compile. Its approach is:
        # - Unlock the dependency we're checking in the requirements.in file
        # - Run `pip-compile` and see what the result is
        class PipCompileVersionResolver
          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/

          attr_reader :dependency, :dependency_files, :credentials

          def initialize(dependency:, dependency_files:, credentials:,
                         unlock_requirement:, latest_allowable_version:)
            @dependency               = dependency
            @dependency_files         = dependency_files
            @credentials              = credentials
            @latest_allowable_version = latest_allowable_version
            @unlock_requirement       = unlock_requirement
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

                # Shell out to pip-compile, generate a new set of requirements.
                # This is slow, as pip-compile needs to do installs.
                cmd = "pyenv exec pip-compile -P #{dependency.name} "\
                      "#{source_pip_config_file_name}"
                run_command(cmd)

                updated_deps =
                  SharedHelpers.run_helper_subprocess(
                    command: "pyenv exec python #{python_helper_path}",
                    function: "parse_requirements",
                    args: [Dir.pwd]
                  )

                updated_deps.
                  select { |dep| normalise(dep["name"]) == dependency.name }.
                  find { |dep| dep["file"] == source_compiled_file_name }&.
                  fetch("version")
              end
            return unless @latest_resolvable_version_string
            Utils::Python::Version.new(@latest_resolvable_version_string)
          end

          def run_command(command)
            command = command.dup
            raw_response = nil
            IO.popen(command, err: %i(child out)) do |process|
              raw_response = process.read
            end

            # Raise an error with the output from the shell session if
            # pip-compile returns a non-zero status
            return if $CHILD_STATUS.success?
            raise SharedHelpers::HelperSubprocessFailed.new(
              raw_response,
              command
            )
          rescue SharedHelpers::HelperSubprocessFailed => error
            unless error.message.include?("InstallationError") ||
                   error.message.include?("Could not find a version")
              raise
            end
            raise if command.start_with?("pyenv local 2.7.15 &&")
            command = "pyenv local 2.7.15 && " +
                      command +
                      " && pyenv local --unset"
            retry
          end

          def write_temporary_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, unlock_dependency(file))
            end
          end

          def unlock_dependency(file)
            return file.content unless file.name.end_with?(".in")
            return file.content unless dependency.version
            return file.content unless unlock_requirement?

            req = dependency.requirements.find { |r| r[:file] == file.name }
            return file.content unless req&.fetch(:requirement)

            FileUpdaters::Python::Pip::RequirementReplacer.new(
              content: file.content,
              dependency_name: dependency.name,
              old_requirement: req[:requirement],
              new_requirement: updated_version_requirement_string
            ).updated_content
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

          def source_pip_config_file_name
            file_from_reqs =
              dependency.requirements.
              map { |r| r[:file] }.
              find { |fn| fn.end_with?(".in") }

            return file_from_reqs if file_from_reqs

            pip_compile_filenames =
              dependency_files.
              select { |f| f.name.end_with?(".in") }.
              map(&:name)

            pip_compile_filenames.find do |fn|
              req_file = dependency_files.
                         find { |f| f.name == fn.gsub(/\.in$/, ".txt") }
              req_file&.content&.include?(dependency.name)
            end
          end

          def source_compiled_file_name
            source_pip_config_file_name.sub(/\.in$/, ".txt")
          end

          def python_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/python/run.py")
          end

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalise(name)
            name.downcase.tr("_", "-").tr(".", "-")
          end
        end
      end
    end
  end
end
