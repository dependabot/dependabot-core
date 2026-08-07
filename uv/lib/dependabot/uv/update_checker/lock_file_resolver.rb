# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/package/package_release"
require "dependabot/package/release_cooldown_options"
require "dependabot/update_checkers/cooldown_calculation"
require "dependabot/uv/version"
require "dependabot/uv/requirement"
require "dependabot/uv/update_checker"
require "dependabot/uv/update_checker/latest_version_finder"
require "dependabot/uv/file_updater/lock_file_updater"

module Dependabot
  module Uv
    class UpdateChecker
      class LockFileResolver
        extend T::Sig

        # Markers in a uv error that indicate a genuine version-solving conflict for the
        # probed candidate (as opposed to workspace/build/tooling failures).
        RESOLUTION_CONFLICT_MARKERS = T.let(
          Regexp.union(
            "No solution found when resolving dependencies",
            "ResolutionImpossible"
          ),
          Regexp
        )

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String),
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            ignored_versions: T::Array[String],
            update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          repo_contents_path: nil,
          security_advisories: [],
          ignored_versions: [],
          update_cooldown: nil
        )
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @repo_contents_path = repo_contents_path
          @security_advisories = security_advisories
          @ignored_versions = ignored_versions
          @update_cooldown = update_cooldown
        end

        sig { params(requirement: T.nilable(String)).returns(T.nilable(Dependabot::Uv::Version)) }
        def latest_resolvable_version(requirement:)
          return nil unless requirement

          req = Uv::Requirement.new(requirement)
          current_version = dependency.version && Uv::Version.new(dependency.version)

          # Probe allowed candidate versions from highest to lowest, returning the
          # first one uv can actually resolve to.
          candidate_versions(req, current_version).each do |candidate|
            return candidate if resolvable_to?(candidate)
          end

          # Otherwise report the current version when it still satisfies the requirement.
          current_version if current_version && req.satisfied_by?(current_version)
        end

        sig { params(_version: T.anything).returns(T::Boolean) }
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

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :update_cooldown

        # Allowed candidate versions (newer than current, satisfying the requirement, not
        # ignored, not yanked, not in cooldown), highest first.
        sig do
          params(
            requirement: Dependabot::Uv::Requirement,
            current_version: T.nilable(Dependabot::Uv::Version)
          ).returns(T::Array[Dependabot::Uv::Version])
        end
        def candidate_versions(requirement, current_version)
          releases = latest_version_finder.available_versions || []

          releases
            .reject(&:yanked?)
            .reject { |release| in_cooldown?(release, current_version) }
            .map { |release| Uv::Version.new(release.version.to_s) }
            .uniq
            .select { |version| candidate?(version, requirement, current_version) }
            .sort
            .reverse
        end

        # Whether the release is still within its cooldown window, applied per release date
        # (mirrors PackageLatestVersionFinder#in_cooldown_period?) rather than as a version ceiling.
        sig do
          params(
            release: Dependabot::Package::PackageRelease,
            current_version: T.nilable(Dependabot::Uv::Version)
          ).returns(T::Boolean)
        end
        def in_cooldown?(release, current_version)
          released_at = release.released_at
          return false unless released_at

          cooldown = update_cooldown
          return false if Dependabot::UpdateCheckers::CooldownCalculation.skip_cooldown?(cooldown, dependency.name)

          days = Dependabot::UpdateCheckers::CooldownCalculation.cooldown_days_for(
            T.must(cooldown), current_version, release.version
          )
          Dependabot::UpdateCheckers::CooldownCalculation.within_cooldown_window?(released_at, days)
        end

        sig do
          params(
            version: Dependabot::Uv::Version,
            requirement: Dependabot::Uv::Requirement,
            current_version: T.nilable(Dependabot::Uv::Version)
          ).returns(T::Boolean)
        end
        def candidate?(version, requirement, current_version)
          return false unless requirement.satisfied_by?(version)
          return false if current_version && version <= current_version
          return false if version.prerelease? && !current_version&.prerelease?
          return false if ignored?(version)

          true
        end

        sig { params(version: Dependabot::Uv::Version).returns(T::Boolean) }
        def ignored?(version)
          ignored_versions.flat_map { |req| Uv::Requirement.requirements_array(req) }
                          .any? { |r| r.satisfied_by?(version) }
        end

        # Runs the uv resolver to check whether the sub-dependency can be bumped to target_version.
        sig { params(target_version: Dependabot::Uv::Version).returns(T::Boolean) }
        def resolvable_to?(target_version)
          updated_dependency = Dependabot::Dependency.new(
            name: dependency.name,
            version: target_version.to_s,
            previous_version: dependency.version,
            requirements: [],
            previous_requirements: [],
            package_manager: "uv"
          )

          FileUpdater::LockFileUpdater.new(
            dependencies: [updated_dependency],
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path
          ).updated_dependency_files

          true
        rescue Dependabot::UpdateNotPossible
          # uv extracted a concrete version conflict for this candidate: not resolvable.
          false
        rescue Dependabot::DependencyFileNotResolvable => e
          # Only a genuine resolver conflict means this candidate is unresolvable; other
          # failures (workspace, build, network, tooling, etc.) must propagate.
          raise unless e.message.match?(RESOLUTION_CONFLICT_MARKERS)

          false
        end

        sig { returns(LatestVersionFinder) }
        def latest_version_finder
          @latest_version_finder ||= T.let(
            LatestVersionFinder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              ignored_versions: ignored_versions,
              security_advisories: security_advisories,
              cooldown_options: update_cooldown,
              raise_on_ignored: false
            ),
            T.nilable(LatestVersionFinder)
          )
        end
      end
    end
  end
end
