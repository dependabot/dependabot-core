# frozen_string_literal: true

require "dependabot/update_checkers/python/pip"
require "dependabot/utils/python/version"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip
        # This class does version resolution for pip-compile. Its approach is:
        # - Run `pip-compile` and see what the result is
        #
        # In future, we should ensure it unlocks the dependency first.
        class PipCompileVersionResolver
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
                  find { |dep| dep["file"] == source_compiled_file_name }.
                  fetch("version")
              end
            return unless @latest_resolvable_version_string
            Utils::Python::Version.new(@latest_resolvable_version_string)
          end

          def run_command(command)
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
          end

          def write_temporary_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end
          end

          def source_pip_config_file_name
            dependency.requirements.
              map { |r| r[:file] }.
              find { |fn| fn.end_with?(".in") }
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
