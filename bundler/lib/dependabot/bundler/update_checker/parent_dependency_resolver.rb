# frozen_string_literal: true

require "dependabot/bundler/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Bundler
    class UpdateChecker
      class ParentDependencyResolver
        require_relative "shared_bundler_helpers"
        include SharedBundlerHelpers

        def initialize(dependency_files:, repo_contents_path:, credentials:)
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        def blocking_parent_dependencies(dependency:, target_version:)
          in_a_native_bundler_context(error_handling: false) do |tmp_dir|
            SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path,
              function: "blocking_parent_dependencies",
              args: {
                dir: tmp_dir,
                dependency_name: dependency.name,
                target_version: target_version,
                credentials: relevant_credentials,
                lockfile_name: lockfile.name,
                using_bundler_2: using_bundler_2?
              }
            )
          end
        end

        private

        attr_reader :dependency_files, :repo_contents_path, :credentials

        def lockfile
          (dependency_files.find { |f| f.name == "Gemfile.lock" } ||
           dependency_files.find { |f| f.name == "gems.locked" })
        end

        def relevant_credentials
          credentials.
            select { |cred| cred["password"] || cred["token"] }.
            select do |cred|
              next true if cred["type"] == "git_source"
              next true if cred["type"] == "rubygems_server"

              false
            end
        end

        def using_bundler_2?
          return unless lockfile

          lockfile.content.match?(/BUNDLED WITH\s+2/m)
        end
      end
    end
  end
end
