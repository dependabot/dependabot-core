# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/uv/version"
require "dependabot/uv/requirement"
require "dependabot/uv/update_checker"

module Dependabot
  module Uv
    class UpdateChecker
      class LockFileResolver
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String)
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:, repo_contents_path: nil)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @repo_contents_path = repo_contents_path
        end

        sig { params(requirement: T.nilable(String)).returns(T.nilable(Dependabot::Uv::Version)) }
        def latest_resolvable_version(requirement:)
          return nil unless requirement

          req = Uv::Requirement.new(requirement)

          # Get the version from the dependency if available
          version_from_dependency = dependency.version && Uv::Version.new(dependency.version)
          return version_from_dependency if version_from_dependency && req.satisfied_by?(version_from_dependency)

          nil
        end

        sig { params(_version: T.untyped).returns(T::Boolean) }
        def resolvable?(_version)
          # Always return true since we don't actually attempt resolution
          # This is just a placeholder implementation
          true
        end

        sig { returns(T.nilable(Dependabot::Uv::Version)) }
        def lowest_resolvable_security_fix_version
          nil
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path
      end
    end
  end
end
