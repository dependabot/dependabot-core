# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bazel/file_updater"
require "dependabot/bazel/package_manager"
require "dependabot/bazel/version"
require "dependabot/shared_helpers"
require "pathname"
require "fileutils"

module Dependabot
  module Bazel
    class FileUpdater < Dependabot::FileUpdaters::Base
      class LockfileUpdater
        extend T::Sig

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            dependencies: T::Array[Dependabot::Dependency],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, dependencies:, credentials:)
          @dependency_files = dependency_files
          @dependencies = dependencies
          @credentials = credentials
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def updated_lockfile
          return nil unless needs_lockfile_update?

          existing_lockfile = lockfile
          updated_content = generate_lockfile_content

          if existing_lockfile
            return nil if existing_lockfile.content == updated_content

            existing_lockfile.dup.tap { |f| f.content = updated_content }
          else
            Dependabot::DependencyFile.new(
              name: "MODULE.bazel.lock",
              content: updated_content,
              directory: module_file.directory
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_bazel_error_for_lockfile(e)
        end

        sig { returns(String) }
        def determine_bazel_version
          # Exact name match: nested .bazelversion files (e.g. from local_path_override
          # modules) pin those modules' Bazel, not this workspace's.
          bazelversion_file = dependency_files.find { |f| f.name == ".bazelversion" }
          Dependabot::Bazel::Version.version_from_file(bazelversion_file) ||
            Dependabot::Bazel::DEFAULT_BAZEL_VERSION
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Boolean) }
        def needs_lockfile_update?
          return false unless module_file?

          dependencies.any? { |dep| bzlmod_dependency?(dep) }
        end

        sig { returns(T::Boolean) }
        def module_file?
          module_files.any?
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def module_files
          @module_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?("MODULE.bazel") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(Dependabot::DependencyFile) }
        def module_file
          T.must(module_files.first)
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          @lockfile ||= T.let(
            dependency_files.find { |f| f.name == "MODULE.bazel.lock" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def bzlmod_dependency?(dependency)
          dependency.requirements.any? { |req| req[:file]&.end_with?("MODULE.bazel") }
        end

        sig { returns(String) }
        def generate_lockfile_content
          base_directory = module_file.directory

          SharedHelpers.in_a_temporary_repo_directory(base_directory, repo_contents_path) do
            write_temporary_dependency_files

            File.write(module_file.name, updated_module_content)

            run_bazel_mod_tidy_command

            File.read("MODULE.bazel.lock")
          end
        end

        sig { returns(String) }
        def updated_module_content
          bzlmod_updater = BzlmodFileUpdater.new(
            dependency_files: dependency_files,
            dependencies: dependencies,
            credentials: credentials
          )

          bzlmod_updater.send(:update_file_content, module_file)
        end

        sig { returns(T.nilable(String)) }
        def repo_contents_path
          # For now, return nil. This can be enhanced later if needed.
          nil
        end

        sig { void }
        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname) if path.include?("/")
            if File.basename(path) == ".bazelversion"
              target = bazelisk_target(file)
              unless target == T.must(file.content).strip
                Dependabot.logger.info("Rewriting #{path} for Bazelisk: #{target.inspect}")
              end
              File.write(path, target)
            else
              File.write(path, T.must(file.content))
            end
          end

          write_bazelversion_if_missing
        end

        # What the temporary .bazelversion should contain for Bazelisk to run: the
        # file's own target (fork entries preserved, wrapper entries stripped),
        # falling back to the default Bazel version for wrapper-only/empty files.
        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def bazelisk_target(file)
          Dependabot::Bazel::Version.bazelisk_target_from_file(file) ||
            Dependabot::Bazel::DEFAULT_BAZEL_VERSION
        end

        sig { void }
        def write_bazelversion_if_missing
          return if dependency_files.any? { |f| f.name == ".bazelversion" }

          bazel_version = determine_bazel_version
          File.write(".bazelversion", bazel_version)
          Dependabot.logger.info("Using Bazel version: #{bazel_version}")
        end

        sig { void }
        def run_bazel_mod_tidy_command
          bazel_command = bazelisk_available? ? "bazelisk" : "bazel"

          SharedHelpers.run_shell_command(
            "#{bazel_command} mod tidy --lockfile_mode=update",
            fingerprint: "#{bazel_command} mod tidy --lockfile_mode=update"
          )

          return if File.exist?("MODULE.bazel.lock")

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: "MODULE.bazel.lock file was not generated",
            error_context: {}
          )
        end

        sig { returns(T::Boolean) }
        def bazelisk_available?
          !!system("which bazelisk > /dev/null 2>&1")
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T.nilable(Dependabot::DependencyFile)) }
        def handle_bazel_error_for_lockfile(error)
          Dependabot.logger.warn("Bazel lockfile generation failed: #{error.message}")

          case error.message
          when /command not found/i, /bazel(isk)?\s*:\s*(command\s+)?not found/i
            raise Dependabot::DependencyFileNotResolvable,
                  "Bazel binary not available. Cannot generate MODULE.bazel.lock file."
          when /module.*not.*found/i, /registry.*not.*found/i
            raise Dependabot::DependencyFileNotResolvable,
                  "Dependency not found in Bazel Central Registry."
          when /network.*error/i, /timeout/i, /connection.*refused/i
            raise Dependabot::DependencyFileNotResolvable,
                  "Network error during lockfile generation. Please try again later."
          when /invalid.*syntax/i, /parse.*error/i
            raise Dependabot::DependencyFileNotParseable,
                  "Invalid MODULE.bazel syntax prevents lockfile generation."
          when /permission.*denied/i
            raise Dependabot::DependencyFileNotResolvable,
                  "Permission error during lockfile generation."
          else
            raise Dependabot::DependencyFileNotResolvable,
                  "Error generating lockfile: #{error.message}"
          end
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(String) }
        def handle_bazel_error(error)
          Dependabot.logger.warn("Bazel lockfile generation failed: #{error.message}")

          case error.message
          when /command not found/i, /bazel(isk)?\s*:\s*(command\s+)?not found/i
            raise Dependabot::DependencyFileNotResolvable,
                  "Bazel binary not available. Cannot generate MODULE.bazel.lock file."
          when /module.*not.*found/i, /registry.*not.*found/i
            raise Dependabot::DependencyFileNotResolvable,
                  "Dependency not found in Bazel Central Registry."
          when /network.*error/i, /timeout/i, /connection.*refused/i
            raise Dependabot::DependencyFileNotResolvable,
                  "Network error during lockfile generation. Please try again later."
          when /invalid.*syntax/i, /parse.*error/i
            raise Dependabot::DependencyFileNotParseable,
                  "Invalid MODULE.bazel syntax prevents lockfile generation."
          when /permission.*denied/i
            raise Dependabot::DependencyFileNotResolvable,
                  "Permission error during lockfile generation."
          else
            raise Dependabot::DependencyFileNotResolvable,
                  "Error generating lockfile: #{error.message}"
          end
        end
      end
    end
  end
end
