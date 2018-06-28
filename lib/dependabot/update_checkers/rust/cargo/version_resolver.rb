# frozen_string_literal: true

require "toml-rb"
require "dependabot/shared_helpers"
require "dependabot/file_parsers/rust/cargo"
require "dependabot/update_checkers/rust/cargo"
require "dependabot/utils/rust/version"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Rust
      class Cargo
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
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files
              set_git_credentials

              # Shell out to Cargo, which handles everything for us, and does
              # so without doing an install (so it's fast).
              command = "cargo update -p #{dependency_spec} --verbose"
              run_shell_command(command)

              new_lockfile_content = File.read("Cargo.lock")
              updated_version = get_version_from_lockfile(new_lockfile_content)

              return if updated_version.nil?
              return updated_version if git_dependency?
              version_class.new(updated_version)
            end
          rescue SharedHelpers::HelperSubprocessFailed => error
            handle_cargo_errors(error)
          ensure
            reset_git_config
          end

          def get_version_from_lockfile(lockfile_content)
            versions = TomlRB.parse(lockfile_content).fetch("package").
                       select { |p| p["name"] == dependency.name }

            updated_version =
              if dependency.top_level?
                versions.max_by { |p| version_class.new(p.fetch("version")) }
              else
                versions.min_by { |p| version_class.new(p.fetch("version")) }
              end

            if git_dependency?
              updated_version.fetch("source").split("#").last
            else
              updated_version.fetch("version")
            end
          end

          def dependency_spec
            spec = dependency.name

            if git_dependency?
              spec += ":#{git_dependency_version}" if git_dependency_version
            elsif dependency.version
              spec += ":#{dependency.version}"
            end

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
              File.write(file.name, file.content)

              FileUtils.mkdir_p(File.join(dir, "src"))
              File.write(File.join(dir, "src/lib.rs"), dummy_app_content)
              File.write(File.join(dir, "src/main.rs"), dummy_app_content)
            end

            File.write(lockfile.name, lockfile.content) if lockfile
          end

          def set_git_credentials
            # This has to be global, otherwise Cargo doesn't pick it up
            run_shell_command(
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

          def reset_git_config
            run_shell_command("git config --global --remove-section credential")
          end

          def handle_cargo_errors(error)
            path_regex =
              Regexp.escape(SharedHelpers::BUMP_TMP_DIR_PATH) + "\/" +
              Regexp.escape(SharedHelpers::BUMP_TMP_FILE_PREFIX) + "[^/]*"
            msg = error.message.gsub(/#{path_regex}/, "dependabot_tmp_dir")

            if error.message.include?("does not have these features")
              # TODO: Ideally we should update the declaration not to ask
              # for the specified features
              return nil
            end
            if error.message.include?("failed to parse lock")
              raise Dependabot::DependencyFileNotResolvable, msg
            end
            raise error
          end

          def git_dependency_version
            return unless lockfile

            TomlRB.parse(lockfile.content).
              fetch("package", []).
              select { |p| p["name"] == dependency.name }.
              find { |p| p["source"].end_with?(dependency.version) }.
              fetch("version")
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

          def git_dependency?
            GitCommitChecker.new(
              dependency: dependency,
              credentials: credentials
            ).git_dependency?
          end

          def version_class
            Utils::Rust::Version
          end
        end
      end
    end
  end
end
