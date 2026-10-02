# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/experiments"
require "dependabot/npm_and_yarn/file_parser"
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
        # @return [Array<Hash{String => Object}]
        #   * name [String] the blocking dependencies name
        #   * version [String] the version of the blocking dependency
        #   * requirement [String] the requirement on the target_dependency
        sig do
          params(
            dependency: Dependabot::Dependency,
            target_version: T.nilable(T.any(String, Dependabot::Version))
          )
            .returns(T::Array[Dependabot::UpdateCheckers::Conflict])
        end
        def conflicting_dependencies(dependency:, target_version:)
          enable_normalized_yarn_traversal = false

          SharedHelpers.in_a_temporary_directory do
            dependency_files_builder = DependencyFilesBuilder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials
            )
            dependency_files_builder.write_temporary_dependency_files

            if dependency_files_builder.yarn_locks.any?
              enable_normalized_yarn_traversal =
                Dependabot::Experiments.enabled?(:enable_yarn_berry_conflicting_dependencies)
            end

            find_conflicting_dependencies(
              dependency_files_builder:,
              dependency:,
              target_version:,
              enable_normalized_yarn_traversal:
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed
          raise if enable_normalized_yarn_traversal

          []
        end

        private

        sig do
          params(
            dependency_files_builder: DependencyFilesBuilder,
            dependency: Dependabot::Dependency,
            target_version: T.nilable(T.any(String, Dependabot::Version)),
            enable_normalized_yarn_traversal: T::Boolean
          )
            .returns(T::Array[Dependabot::UpdateCheckers::Conflict])
        end
        def find_conflicting_dependencies(
          dependency_files_builder:,
          dependency:,
          target_version:,
          enable_normalized_yarn_traversal:
        )
          # TODO: Look into using npm/arborist for parsing yarn lockfiles (there's currently partial yarn support)
          #
          # Prefer the npm conflicting dependency parser if there's both a npm lockfile and a yarn.lock file as the
          # npm parser handles edge cases where the package.json is out of sync with the lockfile, something the yarn
          # parser doesn't deal with at the moment.
          if dependency_files_builder.package_locks.any? ||
             dependency_files_builder.shrinkwraps.any?
            run_conflicting_dependency_helper(
              function: "npm:findConflictingDependencies",
              dependency:,
              target_version:,
              enable_normalized_yarn_traversal: false
            )
          elsif dependency_files_builder.yarn_locks.none? || !enable_normalized_yarn_traversal
            run_conflicting_dependency_helper(
              function: "yarn:findConflictingDependencies",
              dependency:,
              target_version:,
              enable_normalized_yarn_traversal: false
            )
          else
            run_conflicting_dependency_helper(
              function: "yarn:findConflictingDependencies",
              dependency:,
              target_version:,
              enable_normalized_yarn_traversal:
            )
          end
        end

        sig do
          params(
            function: String,
            dependency: Dependabot::Dependency,
            target_version: T.nilable(T.any(String, Dependabot::Version)),
            enable_normalized_yarn_traversal: T::Boolean
          )
            .returns(T::Array[Dependabot::UpdateCheckers::Conflict])
        end
        def run_conflicting_dependency_helper(
          function:,
          dependency:,
          target_version:,
          enable_normalized_yarn_traversal:
        )
          args = T.let(
            [Dir.pwd, dependency.name, target_version.to_s],
            T::Array[T.any(String, T::Boolean)]
          )
          args << enable_normalized_yarn_traversal if function == "yarn:findConflictingDependencies"

          T.cast(
            SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path,
              function: function,
              args:
            ),
            T::Array[Dependabot::UpdateCheckers::Conflict]
          )
        rescue SharedHelpers::HelperSubprocessFailed
          raise if enable_normalized_yarn_traversal

          []
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
      end
    end
  end
end
