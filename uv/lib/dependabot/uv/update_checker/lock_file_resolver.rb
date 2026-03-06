# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/uv/version"
require "dependabot/uv/requirement"
require "dependabot/uv/update_checker"
require "dependabot/uv/update_checker/latest_version_finder"

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
            repo_contents_path: T.nilable(String),
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            ignored_versions: T::Array[String]
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          repo_contents_path: nil,
          security_advisories: [],
          ignored_versions: []
        )
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @repo_contents_path = repo_contents_path
          @security_advisories = security_advisories
          @ignored_versions = ignored_versions
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
          # Delegate to LatestVersionFinder which handles security advisory filtering
          fix_version = latest_version_finder.lowest_security_fix_version
          return nil if fix_version.nil?

          # Return the fix version cast to Uv::Version
          Uv::Version.new(fix_version.to_s)
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

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(LatestVersionFinder) }
        def latest_version_finder
          @latest_version_finder ||= T.let(
            LatestVersionFinder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              ignored_versions: ignored_versions,
              security_advisories: security_advisories,
              raise_on_ignored: false
            ),
            T.nilable(LatestVersionFinder)
          )
        end
      end
    end
  end
end
