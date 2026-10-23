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
            target_version: T.nilable(T.any(String, Dependabot::Version)),
            affected_versions: T.nilable(T::Array[String])
          )
            .returns(T::Array[Dependabot::UpdateCheckers::Conflict])
        end
        def conflicting_dependencies(dependency:, target_version:, affected_versions: nil)
          enable_normalized_yarn_traversal = T.let(false, T::Boolean)

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

              # Normalized traversal needs the target's lockfile entries to tell
              # its locked instances apart.
              dependency_files_builder.write_original_yarn_lockfiles if enable_normalized_yarn_traversal
            end

            find_conflicting_dependencies(
              dependency_files_builder:,
              dependency:,
              target_version:,
              enable_normalized_yarn_traversal:,
              affected_versions: affected_versions || [dependency.version].compact
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
            enable_normalized_yarn_traversal: T::Boolean,
            affected_versions: T::Array[String]
          )
            .returns(T::Array[Dependabot::UpdateCheckers::Conflict])
        end
        def find_conflicting_dependencies(
          dependency_files_builder:,
          dependency:,
          target_version:,
          enable_normalized_yarn_traversal:,
          affected_versions:
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
              enable_normalized_yarn_traversal: false,
              affected_versions:
            )
          elsif dependency_files_builder.yarn_locks.none? || !enable_normalized_yarn_traversal
            run_conflicting_dependency_helper(
              function: "yarn:findConflictingDependencies",
              dependency:,
              target_version:,
              enable_normalized_yarn_traversal: false,
              affected_versions:
            )
          else
            run_conflicting_dependency_helper(
              function: "yarn:findConflictingDependencies",
              dependency:,
              target_version:,
              enable_normalized_yarn_traversal:,
              affected_versions:
            )
          end
        end

        sig do
          params(
            function: String,
            dependency: Dependabot::Dependency,
            target_version: T.nilable(T.any(String, Dependabot::Version)),
            enable_normalized_yarn_traversal: T::Boolean,
            affected_versions: T::Array[String]
          )
            .returns(T::Array[Dependabot::UpdateCheckers::Conflict])
        end
        def run_conflicting_dependency_helper(
          function:,
          dependency:,
          target_version:,
          enable_normalized_yarn_traversal:,
          affected_versions:
        )
          args = T.let(
            [Dir.pwd, dependency.name, target_version.to_s],
            T::Array[T.any(String, T::Boolean, T::Array[String])]
          )
          if function == "yarn:findConflictingDependencies"
            args << enable_normalized_yarn_traversal
            args << affected_versions if enable_normalized_yarn_traversal && affected_versions.any?
          end

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
