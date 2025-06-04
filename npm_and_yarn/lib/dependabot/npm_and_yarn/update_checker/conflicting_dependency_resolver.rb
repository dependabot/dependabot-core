# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/npm_and_yarn/update_checker/dependency_files_builder"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class ConflictingDependencyResolver
        extend T::Sig

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
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
        sig do
          params(
            dependency: Dependabot::Dependency,
            target_version: T.nilable(T.any(String, Dependabot::Version))
          )
            .returns(T::Array[T::Hash[String, String]])
        end
        def conflicting_dependencies(dependency:, target_version:)
          SharedHelpers.in_a_temporary_directory do
            dependency_files_builder = DependencyFilesBuilder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials
            )
            dependency_files_builder.write_temporary_dependency_files

            # TODO: Look into using npm/arborist for parsing yarn lockfiles (there's currently partial yarn support)
            #
            # Prefer the npm conflicting dependency parser if there's both a npm lockfile and a yarn.lock file as the
            # npm parser handles edge cases where the package.json is out of sync with the lockfile, something the yarn
            # parser doesn't deal with at the moment.
            if dependency_files_builder.package_locks.any? ||
               dependency_files_builder.shrinkwraps.any?
              T.cast(
                SharedHelpers.run_helper_subprocess(
                  command: NativeHelpers.helper_path,
                  function: "npm:findConflictingDependencies",
                  args: [Dir.pwd, dependency.name, target_version.to_s]
                ),
                T::Array[T::Hash[String, String]]
              )
            else
              T.cast(
                SharedHelpers.run_helper_subprocess(
                  command: NativeHelpers.helper_path,
                  function: "yarn:findConflictingDependencies",
                  args: [Dir.pwd, dependency.name, target_version.to_s]
                ),
                T::Array[T::Hash[String, String]]
              )
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed
          []
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
      end
    end
  end
end
