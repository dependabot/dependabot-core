# typed: true
# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/logger"
require "dependabot/devcontainers/utils"

module Dependabot
  module Devcontainers
    class FileUpdater < Dependabot::FileUpdaters::Base
      class ConfigUpdater
        def initialize(feature:, requirement:, manifest:, repo_contents_path:, credentials:)
          @feature = feature
          @requirement = requirement
          @manifest = manifest
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        def update
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials) do
              update_manifest(
                target_requirement: requirement[:requirement],
                target_version: requirement[:metadata][:latest]
              )

              [File.read(manifest_name), File.read(lockfile_name)].compact
            end
          end
        end

        private

        def base_dir
          File.dirname(manifest.name)
        end

        def manifest_name
          File.basename(manifest.name)
        end

        def lockfile_name
          Utils.expected_lockfile_name(manifest_name)
        end

        def update_manifest(target_requirement:, target_version:)
          # First force target version to upgrade lockfile. I believe the CLI
          # shoudl automatically upgrade the lockfile directly, but needs a
          # explicit version at the moment. If
          # https://github.com/devcontainers/cli/issues/715 is implement, this
          # first invocation can be removed
          run_devcontainer_upgrade(target_version)

          run_devcontainer_upgrade(target_requirement)
        end

        def run_devcontainer_upgrade(target_version)
          cmd = "devcontainer upgrade " \
                "--workspace-folder . " \
                "--feature #{feature} " \
                "--config #{manifest_name} " \
                "--target-version #{target_version}"

          Dependabot.logger.info("Running command: `#{cmd}`")

          SharedHelpers.run_shell_command(cmd, stderr_to_stdout: false)
        end

        attr_reader :feature, :requirement, :manifest, :repo_contents_path, :credentials
      end
    end
  end
end
