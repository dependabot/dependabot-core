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
          NOT_FOUND_REGEX = /failed to list versions for (?<repo_url>.*): ERROR/

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
            base_directory = File.join("src", "project",
                                       dependency_files.first.directory)
            base_parts = base_directory.split("/").length
            updated_version =
              SharedHelpers.in_a_temporary_directory(base_directory) do |dir|
                write_temporary_dependency_files

                SharedHelpers.with_git_configured(credentials: credentials) do
                  # Shell out to dep, which handles everything for us, and does
                  # so without doing an install (so it's fast).
                  command = "dep ensure -update --no-vendor #{dependency.name}"
                  dir_parts = dir.realpath.to_s.split("/")
                  gopath = File.join(dir_parts[0..-(base_parts + 1)])
                  run_shell_command(command, "GOPATH" => gopath)
                end

                new_lockfile_content = File.read("Gopkg.lock")

                get_version_from_lockfile(new_lockfile_content)
              end

            updated_version
          rescue SharedHelpers::HelperSubprocessFailed => error
            handle_dep_errors(error)
          end

          def get_version_from_lockfile(lockfile_content)
            package = TomlRB.parse(lockfile_content).fetch("projects").
                      find { |p| p["name"] == dependency.name }

            version = package["version"]

            if version && version_class.correct?(version.sub(/^v?/, ""))
              version_class.new(version.sub(/^v?/, ""))
            elsif version
              version
            else
              package.fetch("revision")
            end
          end

          def handle_dep_errors(error)
            if error.message.include?("Repository not found")
              url = error.message.match(NOT_FOUND_REGEX).
                    named_captures.fetch("repo_url")

              raise Dependabot::GitDependenciesNotReachable, url
            end

            raise
          end

          def run_shell_command(command, env = {})
            raw_response = nil
            IO.popen(env, command, err: %i(child out)) do |process|
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

          def dummy_app_content
            base = "package main\n\n"\
                   "import \"fmt\"\n\n"

            packages_to_import.each { |nm| base += "import \"#{nm}\"\n\n" }

            base + "func main() {\n  fmt.Printf(\"hello, world\\n\")\n}"
          end

          def packages_to_import
            return [] unless lockfile
            parsed_lockfile = TomlRB.parse(lockfile.content)

            # If the lockfile was created using dep v0.5.0+ then it will tell us
            # exactly which packages to import
            if parsed_lockfile.dig("solve-meta", "input-imports")
              return parsed_lockfile.dig("solve-meta", "input-imports")
            end

            # Otherwise we have no way of knowing, so import everything in the
            # lockfile that isn't marked as internal
            parsed_lockfile.fetch("projects").flat_map do |dep|
              dep["packages"].map do |package|
                next if package.start_with?("internal")
                package == "." ? dep["name"] : File.join(dep["name"], package)
              end.compact
            end
          end

          def lockfile
            @lockfile = dependency_files.find { |f| f.name == "Gopkg.lock" }
          end

          def version_class
            Utils.version_class_for_package_manager(dependency.package_manager)
          end
        end
      end
    end
  end
end
