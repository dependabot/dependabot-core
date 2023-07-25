# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      class LockfileUpdater
        def initialize(dependencies:, manifest:, repo_contents_path:, credentials:)
          @dependencies = dependencies
          @manifest = manifest
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        def updated_lockfile_content
          SharedHelpers.in_a_temporary_repo_directory(manifest.directory, repo_contents_path) do
            File.write(manifest.name, manifest.content)

            SharedHelpers.with_git_configured(credentials: credentials) do
              SharedHelpers.run_shell_command(
                "swift package update #{dependencies.map(&:name).join(' ')}",
                fingerprint: "swift package update <dependency_name>"
              )

              File.read("Package.resolved")
            end
          end
        end

        private

        attr_reader :dependencies, :manifest, :repo_contents_path, :credentials
      end
    end
  end
end
