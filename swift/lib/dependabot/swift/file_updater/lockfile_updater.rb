# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/logger"
require "sorbet-runtime"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      class LockfileUpdater
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            manifest: Dependabot::DependencyFile,
            repo_contents_path: String,
            credentials: T::Array[Dependabot::Credential],
            target_version: T.nilable(String)
          )
            .void
        end
        def initialize(dependency:, manifest:, repo_contents_path:, credentials:, target_version: nil)
          @dependency = dependency
          @manifest = manifest
          @repo_contents_path = repo_contents_path
          @credentials = credentials
          @target_version = target_version
        end

        sig { returns(String) }
        def updated_lockfile_content
          SharedHelpers.in_a_temporary_repo_directory(manifest.directory, repo_contents_path) do
            File.write(manifest.name, manifest.content)

            SharedHelpers.with_git_configured(credentials: credentials) do
              try_lockfile_update(dependency.metadata[:identity])

              File.read("Package.resolved")
            end
          end
        end

        private

        sig { params(dependency_name: String).void }
        def try_lockfile_update(dependency_name)
          if target_version
            SharedHelpers.run_shell_command(
              "swift package resolve #{dependency_name} --version #{target_version}",
              fingerprint: "swift package resolve <dependency_name> --version <target_version>"
            )
          else
            SharedHelpers.run_shell_command(
              "swift package update #{dependency_name}",
              fingerprint: "swift package update <dependency_name>"
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          # This class is not only used for final lockfile updates, but for
          # checking resolvability. So resolvability errors here are expected in
          # certain situations and will result in `no_update_possible` outcomes.
          # That said, since we're swallowing all errors we at least log them to ease debugging.
          Dependabot.logger.info("Lockfile failed to be updated due to error:\n#{e.message}")
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { returns(String) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :target_version
      end
    end
  end
end
