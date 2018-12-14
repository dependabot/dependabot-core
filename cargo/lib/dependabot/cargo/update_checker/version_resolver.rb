# frozen_string_literal: true

require "toml-rb"
require "dependabot/shared_helpers"
require "dependabot/cargo/update_checker"
require "dependabot/cargo/version"
require "dependabot/errors"

module Dependabot
  module Cargo
    class UpdateChecker
      class VersionResolver
        UNABLE_TO_UPDATE =
          /Unable to update (?<url>.*?)$/.freeze
        BRANCH_NOT_FOUND_REGEX =
          /#{UNABLE_TO_UPDATE}.*to find branch `(?<branch>[^`]+)`/m.freeze
        REF_NOT_FOUND_REGEX =
          /#{UNABLE_TO_UPDATE}.*revspec '.*' not found/m.freeze

        def initialize(dependency:, credentials:,
                       original_dependency_files:, prepared_dependency_files:)
          @dependency = dependency
          @prepared_dependency_files = prepared_dependency_files
          @original_dependency_files = original_dependency_files
          @credentials = credentials
        end

        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        private

        attr_reader :dependency, :credentials,
                    :prepared_dependency_files, :original_dependency_files

        def fetch_latest_resolvable_version
          base_directory = prepared_dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files

            SharedHelpers.with_git_configured(credentials: credentials) do
              # Shell out to Cargo, which handles everything for us, and does
              # so without doing an install (so it's fast).
              command = "cargo update -p #{dependency_spec} --verbose"
              run_cargo_command(command)
            end

            new_lockfile_content = File.read("Cargo.lock")
            updated_version = get_version_from_lockfile(new_lockfile_content)

            return if updated_version.nil?
            return updated_version if git_dependency?

            version_class.new(updated_version)
          end
        rescue SharedHelpers::HelperSubprocessFailed => error
          handle_cargo_errors(error)
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

        def run_cargo_command(command)
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

        def write_temporary_dependency_files(prepared: true)
          write_manifest_files(prepared: prepared)

          File.write(lockfile.name, lockfile.content) if lockfile
          File.write(toolchain.name, toolchain.content) if toolchain
        end

        def handle_cargo_errors(error)
          if error.message.include?("does not have these features")
            # TODO: Ideally we should update the declaration not to ask
            # for the specified features
            return nil
          end

          if error.message.match?(BRANCH_NOT_FOUND_REGEX)
            dependency_url =
              error.message.match(BRANCH_NOT_FOUND_REGEX).
              named_captures.fetch("url").split(/[#?]/).first
            raise Dependabot::GitDependencyReferenceNotFound, dependency_url
          end

          if error.message.match?(REF_NOT_FOUND_REGEX)
            dependency_url =
              error.message.match(REF_NOT_FOUND_REGEX).
              named_captures.fetch("url").split(/[#?]/).first
            raise Dependabot::GitDependencyReferenceNotFound, dependency_url
          end

          if resolvability_error?(error.message)
            raise Dependabot::DependencyFileNotResolvable, error.message
          end

          raise error
        end

        def resolvability_error?(message)
          return true if message.include?("failed to parse lock")
          return true if message.include?("believes it's in a workspace")
          return true if message.include?("wasn't a root")
          return true if message.include?("requires a nightly version")
          return true if message.match?(/feature `[^\`]+` is required/)

          !original_requirements_resolvable?
        end

        def original_requirements_resolvable?
          base_directory = original_dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files(prepared: false)

            SharedHelpers.with_git_configured(credentials: credentials) do
              command = "cargo update -p #{dependency_spec} --verbose"
              run_cargo_command(command)
            end
          end

          true
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.include?("no matching version") ||
                       error.message.include?("failed to select a version")

          false
        end

        def write_manifest_files(prepared: true)
          manifest_files = if prepared then prepared_manifest_files
                           else original_manifest_files
                           end

          manifest_files.each do |file|
            path = file.name
            dir = Pathname.new(path).dirname
            FileUtils.mkdir_p(dir)
            File.write(file.name, sanitized_manifest_content(file.content))

            FileUtils.mkdir_p(File.join(dir, "src"))
            File.write(File.join(dir, "src/lib.rs"), dummy_app_content)
            File.write(File.join(dir, "src/main.rs"), dummy_app_content)
          end
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

        def sanitized_manifest_content(content)
          object = TomlRB.parse(content)

          package_name = object.dig("package", "name")
          return content unless package_name&.match?(/[\{\}]/)

          if lockfile
            raise "Sanitizing name for pkg with lockfile. Investigate!"
          end

          object["package"]["name"] = "sanitized"
          TomlRB.dump(object)
        end

        def prepared_manifest_files
          @prepared_manifest_files ||=
            prepared_dependency_files.
            select { |f| f.name.end_with?("Cargo.toml") }
        end

        def original_manifest_files
          @original_manifest_files ||=
            original_dependency_files.
            select { |f| f.name.end_with?("Cargo.toml") }
        end

        def lockfile
          @lockfile ||= prepared_dependency_files.
                        find { |f| f.name == "Cargo.lock" }
        end

        def toolchain
          @toolchain ||= prepared_dependency_files.
                         find { |f| f.name == "rust-toolchain" }
        end

        def git_dependency?
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ).git_dependency?
        end

        def version_class
          Cargo::Version
        end
      end
    end
  end
end
