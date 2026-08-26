# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/errors"
require "dependabot/package/release_cooldown_options"
require "dependabot/update_checkers/version_filters"
require "dependabot/uv/version"
require "dependabot/uv/file_updater/lock_file_error_handler"
require "dependabot/uv/file_updater/lock_file_updater"
require "dependabot/uv/name_normaliser"
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
          @latest_resolvable_versions = T.let(
            {},
            T::Hash[String, T.nilable(Dependabot::Uv::Version)]
          )
          @resolved_versions = T.let(
            {},
            T::Hash[String, T.nilable(Dependabot::Uv::Version)]
          )
          @resolvable_versions = T.let({}, T::Hash[String, T::Boolean])
        end

        sig { params(requirement: T.nilable(String)).returns(T.nilable(Dependabot::Uv::Version)) }
        def latest_resolvable_version(requirement:)
          return nil unless requirement
          return @latest_resolvable_versions[requirement] if @latest_resolvable_versions.key?(requirement)

          @latest_resolvable_versions[requirement] = fetch_latest_resolvable_version(requirement)
        end

        sig { params(version: Gem::Version).returns(T::Boolean) }
        def resolvable?(version:)
          target_version = Uv::Version.new(version.to_s)
          key = target_version.to_s
          return T.must(@resolvable_versions[key]) if @resolvable_versions.key?(key)

          @resolvable_versions[key] = resolved_version("==#{key}", target_version)&.to_s == key
        end

        sig { returns(T.nilable(Dependabot::Uv::Version)) }
        def lowest_resolvable_security_fix_version
          # Delegate to LatestVersionFinder which handles security advisory filtering
          fix_version = latest_version_finder.lowest_security_fix_version
          return nil unless fix_version
          return nil unless resolvable?(version: fix_version)

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

        sig { params(requirement_string: String).returns(T.nilable(Dependabot::Uv::Version)) }
        def fetch_latest_resolvable_version(requirement_string)
          requirement = Uv::Requirement.new(requirement_string)
          current_version = dependency.version && Uv::Version.new(dependency.version)
          eligible_versions = eligible_versions(requirement, current_version)
          return current_version if no_newer_eligible_version?(requirement, current_version, eligible_versions)

          native_version = resolved_version(
            policy_requirement(requirement_string, requirement, current_version, eligible_versions),
            nil
          )
          return native_version if eligible_native_version?(requirement, native_version, eligible_versions)

          current_version if current_version && requirement.satisfied_by?(current_version)
        end

        sig do
          params(
            requirement: Dependabot::Uv::Requirement,
            current_version: T.nilable(Dependabot::Uv::Version),
            eligible_versions: T.nilable(T::Array[Dependabot::Uv::Version])
          ).returns(T::Boolean)
        end
        def no_newer_eligible_version?(requirement, current_version, eligible_versions)
          return false unless current_version && eligible_versions

          requirement.satisfied_by?(current_version) && eligible_versions.empty?
        end

        sig do
          params(
            requirement: Dependabot::Uv::Requirement,
            native_version: T.nilable(Dependabot::Uv::Version),
            eligible_versions: T.nilable(T::Array[Dependabot::Uv::Version])
          ).returns(T::Boolean)
        end
        def eligible_native_version?(requirement, native_version, eligible_versions)
          return false unless native_version && requirement.satisfied_by?(native_version)

          !eligible_versions || eligible_versions.include?(native_version)
        end

        sig do
          params(
            requirement: Dependabot::Uv::Requirement,
            current_version: T.nilable(Dependabot::Uv::Version)
          ).returns(T.nilable(T::Array[Dependabot::Uv::Version]))
        end
        def eligible_versions(requirement, current_version)
          releases = latest_version_finder.eligible_releases
          return unless releases

          releases = Dependabot::UpdateCheckers::VersionFilters
                     .filter_vulnerable_versions(releases, security_advisories)
          releases
            .map { |release| Uv::Version.new(release.version.to_s) }
            .select { |version| requirement.satisfied_by?(version) && (!current_version || version > current_version) }
        end

        sig do
          params(
            requirement_string: String,
            requirement: Dependabot::Uv::Requirement,
            current_version: T.nilable(Dependabot::Uv::Version),
            eligible_versions: T.nilable(T::Array[Dependabot::Uv::Version])
          ).returns(String)
        end
        def policy_requirement(requirement_string, requirement, current_version, eligible_versions)
          releases = latest_version_finder.available_versions
          return requirement_string unless releases && eligible_versions

          excluded_versions = releases
                              .map { |release| Uv::Version.new(release.version.to_s) }
                              .select do |version|
            requirement.satisfied_by?(version) &&
              (!current_version || version > current_version) &&
              !eligible_versions.include?(version)
          end

          ([requirement_string] + excluded_versions.map { |version| "!=#{version}" }).join(",")
        end

        sig do
          params(
            requirement_string: String,
            target_version: T.nilable(Dependabot::Uv::Version)
          )
            .returns(T.nilable(Dependabot::Uv::Version))
        end
        def resolved_version(requirement_string, target_version)
          return @resolved_versions[requirement_string] if @resolved_versions.key?(requirement_string)

          @resolved_versions[requirement_string] = run_resolution(requirement_string, target_version)
        end

        sig do
          params(
            requirement_string: String,
            target_version: T.nilable(Dependabot::Uv::Version)
          )
            .returns(T.nilable(Dependabot::Uv::Version))
        end
        def run_resolution(requirement_string, target_version)
          updated_dependency = Dependabot::Dependency.new(
            name: dependency.name,
            version: nil,
            previous_version: dependency.version,
            requirements: [],
            previous_requirements: [],
            package_manager: dependency.package_manager
          )

          updated_files = FileUpdater::LockFileUpdater.new(
            dependencies: [updated_dependency],
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            target_requirement: requirement_string
          ).updated_dependency_files

          lockfile = updated_files.find { |file| file.name == "uv.lock" } || original_lockfile
          resolved_locked_version(T.must(lockfile), target_version)
        rescue Dependabot::DependencyFileContentNotChanged
          resolved_locked_version(T.must(original_lockfile), target_version)
        rescue Dependabot::UpdateNotPossible
          nil
        rescue Dependabot::DependencyFileNotResolvable => e
          conflict = e.message.match?(FileUpdater::LockFileErrorHandler::UV_UNRESOLVABLE_REGEX) ||
                     e.message.include?(FileUpdater::LockFileErrorHandler::RESOLUTION_IMPOSSIBLE_ERROR)
          raise unless conflict

          nil
        end

        sig do
          params(
            lockfile: Dependabot::DependencyFile,
            target_version: T.nilable(Dependabot::Uv::Version)
          ).returns(T.nilable(Dependabot::Uv::Version))
        end
        def resolved_locked_version(lockfile, target_version)
          original_versions = locked_versions(T.must(original_lockfile))
          updated_versions = locked_versions(lockfile)
          current_version = dependency.version && Uv::Version.new(dependency.version)
          return nil unless current_version && original_versions.min == current_version
          return current_version if updated_versions.include?(current_version)

          updated_version = updated_versions.min
          return target_version if target_version && updated_version == target_version
          return nil if target_version

          updated_version
        end

        sig do
          params(lockfile: Dependabot::DependencyFile)
            .returns(T::Array[Dependabot::Uv::Version])
        end
        def locked_versions(lockfile)
          parsed = T.cast(TomlRB.parse(T.must(lockfile.content)), T::Hash[String, Object])
          packages = T.cast(parsed["package"], T.nilable(T::Array[T::Hash[String, Object]])) || []
          dependency_name = NameNormaliser.normalise(dependency.name)
          versions = T.let([], T::Array[Dependabot::Uv::Version])
          packages.each do |package|
            package_name = T.cast(package["name"], T.nilable(String))
            package_version = T.cast(package["version"], T.nilable(String))
            next unless package_name && NameNormaliser.normalise(package_name) == dependency_name
            next unless Uv::Version.correct?(package_version)

            versions << Uv::Version.new(package_version)
          end

          versions
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def original_lockfile
          dependency_files.find { |file| file.name == "uv.lock" }
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
