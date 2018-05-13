# frozen_string_literal: true

require "toml-rb"
require "dependabot/shared_helpers"
require "dependabot/file_parsers/rust/cargo"
require "dependabot/update_checkers/rust/cargo"
require "dependabot/utils/rust/version"

module Dependabot
  module UpdateCheckers
    module Rust
      class Cargo
        class VersionResolver
          def initialize(dependency:, dependency_files:,
                         requirements_to_unlock:, credentials:)
            @dependency = dependency
            @dependency_files = dependency_files
            @requirements_to_unlock = requirements_to_unlock
            @credentials = credentials
          end

          def latest_resolvable_version
            @latest_resolvable_version ||= fetch_latest_resolvable_version
          end

          private

          attr_reader :dependency, :dependency_files, :requirements_to_unlock,
                      :credentials

          def fetch_latest_resolvable_version
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files
              set_git_credentials

              # Shell out to Cargo, which handles everything for us, and does
              # so without doing an install (so it's fast).
              command = "cargo update -p #{dependency_spec}"
              run_shell_command(command)

              updated_versions =
                TomlRB.parse(File.read("Cargo.lock")).fetch("package").
                select { |p| p["name"] == dependency.name }

              updated_version =
                if dependency.top_level?
                  updated_versions.
                    max_by { |p| Utils::Rust::Version.new(p.fetch("version")) }.
                    fetch("version")
                else
                  updated_versions.
                    min_by { |p| Utils::Rust::Version.new(p.fetch("version")) }.
                    fetch("version")
                end

              return updated_version if updated_version.nil?
              Utils::Rust::Version.new(updated_version)
            end
          rescue SharedHelpers::HelperSubprocessFailed => error
            handle_cargo_errors(error)
          end

          def dependency_spec
            spec = dependency.name
            spec += ":#{dependency.version}" if dependency.version
            spec
          end

          def run_shell_command(command)
            raw_response = nil
            IO.popen(command, err: %i(child out)) do |process|
              raw_response = process.read
            end

            # Raise an error with the output from the shell session if Cargo
            # returns a non-zero status
            return if $CHILD_STATUS.success?
            raise SharedHelpers::HelperSubprocessFailed.new(
              raw_response,
              command
            )
          end

          def write_temporary_dependency_files
            manifest_files.each do |file|
              path = file.name
              dir = Pathname.new(path).dirname
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(file.name, updated_manifest_file_content(file))

              FileUtils.mkdir_p(File.join(dir, "src"))
              File.write(File.join(dir, "src/lib.rs"), dummy_app_content)
              File.write(File.join(dir, "src/main.rs"), dummy_app_content)
            end

            File.write(lockfile.name, lockfile.content) if lockfile
          end

          def set_git_credentials
            # This has to be global, otherwise Cargo doesn't pick it up
            run_shell_command(
              "git init && "\
              "git config --global --replace-all credential.helper "\
              "'store --file=#{Dir.pwd}/git.store'"
            )

            git_store_content = ""
            credentials.each do |cred|
              next unless cred["type"] == "git_source"

              authenticated_url =
                "https://#{cred.fetch('username')}:#{cred.fetch('password')}"\
                "@#{cred.fetch('host')}"

              git_store_content += authenticated_url + "\n"
            end

            File.write("git.store", git_store_content)
          end

          def handle_cargo_errors(error)
            if error.message.include?("does not have these features")
              # TODO: Ideally we should update the declaration not to ask
              # for the specified features
              return nil
            end
            raise error
          end

          # Note: We don't need to care about formatting in this method, since
          # we're only using the manifest to find the latest resolvable version
          def updated_manifest_file_content(file)
            return file.content if requirements_to_unlock == :none
            parsed_manifest = TomlRB.parse(file.content)

            FileParsers::Rust::Cargo::DEPENDENCY_TYPES.each do |type|
              next unless (req = parsed_manifest.dig(type, dependency.name))
              updated_req =
                if dependency.version then ">= #{dependency.version}"
                else ">= 0"
                end

              if req.is_a?(Hash)
                parsed_manifest[type][dependency.name]["version"] = updated_req
              else
                parsed_manifest[type][dependency.name] = updated_req
              end
            end

            TomlRB.dump(parsed_manifest)
          end

          def dummy_app_content
            %{fn main() {\nprintln!("Hello, world!");\n}}
          end

          def manifest_files
            @manifest_files ||=
              dependency_files.select { |f| f.name.end_with?("Cargo.toml") }
          end

          def lockfile
            @lockfile ||= dependency_files.find { |f| f.name == "Cargo.lock" }
          end
        end
      end
    end
  end
end
