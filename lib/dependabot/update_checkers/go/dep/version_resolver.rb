# frozen_string_literal: true

require "toml-rb"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/go/dep"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Go
      class Dep
        class VersionResolver
          def initialize(dependency:, dependency_files:, credentials:)
            @dependency = dependency
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def latest_resolvable_version
            @latest_resolvable_version ||= fetch_latest_resolvable_version
          end

          private

          attr_reader :dependency, :dependency_files, :credentials

          def fetch_latest_resolvable_version
            updated_version =
              Dir.chdir(go_dir) do
                write_temporary_dependency_files

                SharedHelpers.with_git_configured(credentials: credentials) do
                  # Shell out to dep, which handles everything for us, and does
                  # so without doing an install (so it's fast).
                  command = "dep ensure -update --no-vendor #{dependency.name}"
                  run_shell_command(command)
                end

                new_lockfile_content = File.read("Gopkg.lock")

                get_version_from_lockfile(new_lockfile_content)
              end

            FileUtils.rm_rf(go_dir)
            updated_version
          end

          def get_version_from_lockfile(lockfile_content)
            package = TomlRB.parse(lockfile_content).fetch("projects").
                      find { |p| p["name"] == dependency.name }

            if package["version"]
              version_class.new(package["version"].sub(/^v?/, ""))
            else
              package.fetch("revision")
            end
          end

          def run_shell_command(command)
            raw_response = nil
            IO.popen(command, err: %i(child out)) do |process|
              raw_response = process.read
            end

            # Raise an error with the output from the shell session if dep
            # returns a non-zero status
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
              File.write(file.name, file.content)
            end

            File.write("hello.go", dummy_app_content)
          end

          def go_dir
            # Work in a directory called "$HOME/go/src/dependabot-tmp".
            # TODO: This should pick up what the user's actual GOPATH is.
            go_dir = File.join(Dir.home, "go", "src", "dependabot-tmp")
            FileUtils.mkdir_p(go_dir)
            go_dir
          end

          def dummy_app_content
            "package main\n\nimport \"fmt\"\n\nfunc main() {\n"\
            "  fmt.Printf(\"hello, world\\n\")\n}"
          end

          def version_class
            Utils.version_class_for_package_manager(dependency.package_manager)
          end
        end
      end
    end
  end
end
