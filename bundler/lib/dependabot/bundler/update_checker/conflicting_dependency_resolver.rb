# typed: strict
# frozen_string_literal: true

require "dependabot/bundler/update_checker"
require "dependabot/bundler/native_helpers"
require "dependabot/bundler/helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Bundler
    class UpdateChecker < UpdateCheckers::Base
      class ConflictingDependencyResolver
        extend T::Sig

        require_relative "shared_bundler_helpers"

        include SharedBundlerHelpers

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :options

        sig { override.returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { override.returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { override.returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            repo_contents_path: T.nilable(String),
            credentials: T::Array[Dependabot::Credential],
            options: T::Hash[Symbol, T.untyped]
          )
            .void
        end
        def initialize(dependency_files:, repo_contents_path:, credentials:, options:)
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
          @options = options
        end

        # Finds any dependencies in the lockfile that have a subdependency on
        # the given dependency that does not satisfly the target_version.
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
            target_version: String
          )
            .returns(T::Array[T::Hash[String, String]])
        end
        def conflicting_dependencies(dependency:, target_version:)
          return [] if lockfile.nil?

          in_a_native_bundler_context(error_handling: false) do |tmp_dir|
            NativeHelpers.run_bundler_subprocess(
              bundler_version: bundler_version,
              function: "conflicting_dependencies",
              options: options,
              args: {
                dir: tmp_dir,
                dependency_name: dependency.name,
                target_version: target_version,
                credentials: credentials,
                lockfile_name: T.must(lockfile).name
              }
            )
          end
        end

        private

        sig { override.returns(String) }
        def bundler_version
          @bundler_version ||= T.let(
            Helpers.bundler_version(lockfile),
            T.nilable(String)
          )
        end
      end
    end
  end
end
