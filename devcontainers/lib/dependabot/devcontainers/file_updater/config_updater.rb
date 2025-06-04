# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/logger"
require "dependabot/devcontainers/utils"
require "dependabot/devcontainers/version"

module Dependabot
  module Devcontainers
    class FileUpdater < Dependabot::FileUpdaters::Base
      class ConfigUpdater
        extend T::Sig

        sig do
          params(
            feature: String,
            requirement: T.any(String, Dependabot::Devcontainers::Version),
            version: String,
            manifest: Dependabot::DependencyFile,
            repo_contents_path: String,
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(feature:, requirement:, version:, manifest:, repo_contents_path:, credentials:)
          @feature = feature
          @requirement = requirement
          @version = version
          @manifest = manifest
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        sig { returns(T::Array[String]) }
        def update
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials) do
              update_manifests(
                target_requirement: requirement,
                target_version: version
              )

              [File.read(manifest_name), File.read(lockfile_name)].compact
            end
          end
        end

        private

        sig { returns(String) }
        def base_dir
          File.dirname(manifest.path)
        end

        sig { returns(String) }
        def manifest_name
          File.basename(manifest.path)
        end

        sig { returns(String) }
        def lockfile_name
          Utils.expected_lockfile_name(manifest_name)
        end

        sig do
          params(
            target_requirement: T.any(String, Dependabot::Devcontainers::Version),
            target_version: String
          )
            .void
        end
        def update_manifests(target_requirement:, target_version:)
          # First force target version to upgrade lockfile.
          run_devcontainer_upgrade(target_version)

          # Now replace specific version back with target requirement
          force_target_requirement(manifest_name, from: target_version, to: target_requirement)
          force_target_requirement(lockfile_name, from: target_version, to: target_requirement)
        end

        sig { params(file_name: String, from: String, to: T.any(String, Dependabot::Devcontainers::Version)).void }
        def force_target_requirement(file_name, from:, to:)
          File.write(file_name, File.read(file_name).gsub("#{feature}:#{from}", "#{feature}:#{to}"))
        end

        sig { params(target_version: String).void }
        def run_devcontainer_upgrade(target_version)
          cmd = "devcontainer upgrade " \
                "--workspace-folder . " \
                "--feature #{feature} " \
                "--config #{manifest_name} " \
                "--target-version #{target_version}"

          Dependabot.logger.info("Running command: `#{cmd}`")

          SharedHelpers.run_shell_command(cmd, stderr_to_stdout: false)
        end

        sig { returns(String) }
        attr_reader :feature

        sig { returns(T.any(String, Dependabot::Devcontainers::Version)) }
        attr_reader :requirement

        sig { returns(String) }
        attr_reader :version

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { returns(String) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
      end
    end
  end
end
