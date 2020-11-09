# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/file_updater/npmrc_builder"
require "dependabot/npm_and_yarn/file_updater/package_json_preparer"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/npm_and_yarn/sub_dependency_files_filterer"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/npm_and_yarn/update_checker/dependency_files_builder"
require "dependabot/npm_and_yarn/version"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class ConflictingDependencyResolver
        def initialize(dependency_files:, credentials:)
          @dependency_files = dependency_files
          @credentials = credentials
        end

        # Finds any dependencies in the `yarn.lock` or `package-lock.json` that
        # have a subdependency on the given dependency that does not satisfly
        # the target_version.
        #
        # @param dependency [Dependabot::Dependency] the dependency to check
        # @param target_version [String] the version to check
        # @return [Array<Hash{String => String}]
        #   * name [String] the blocking dependencies name
        #   * version [String] the version of the blocking dependency
        #   * requirement [String] the requirement on the target_dependency
        def conflicting_dependencies(dependency:, target_version:)
          SharedHelpers.in_a_temporary_directory do
            DependencyFilesBuilder.new(dependency_files: dependency_files, credentials: credentials).
              write_temporary_dependency_files

            SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path,
              # We always run in the `npm` namespace as this helper handles both
              # package-lock.json and yarn.lock files.
              function: "npm:findConflictingDependencies",
              args: [Dir.pwd, dependency.name, target_version.to_s]
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed
          []
        end

        private

        attr_reader :dependency_files, :credentials
      end
    end
  end
end
