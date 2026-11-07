# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

require "dependabot/vcpkg/package/versions_database"

module Dependabot
  module Vcpkg
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/security_fix_resolver"

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        # A security fix may pin a version the baseline would never select, so it decides where
        # this dependency is heading.
        fix = security_fix
        return fix.version if fix

        # A port with no `version>=` constraint takes its version from the registry baseline, so
        # the way to move it forwards is to move the baseline. Reporting it as already current
        # keeps routine runs from pinning a constraint the manifest never had.
        return dependency.numeric_version if baseline_governed?

        @latest_version ||= T.let(
          latest_version_finder.latest_version,
          T.nilable(T.any(String, Dependabot::Version))
        )
      end

      # Vcpkg baselines don't have resolvability issues since we're dealing with
      # git tags from the official repository, so these methods delegate to latest_version
      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version = latest_version

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock = latest_version

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version = security_fix&.version

      # A port fix is applied by editing the manifest, so nothing further can make it unresolvable.
      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version = lowest_security_fix_version

      # The release tag for the current baseline commit SHA (else the SHA), so the
      # PR title's "from" shows the tag, not the "master" ref.
      sig { params(_updated_version: T.any(String, Gem::Version)).returns(T.nilable(String)) }
      def latest_resolvable_previous_version(_updated_version)
        current_version = dependency.version
        return current_version unless registry_dependency? && current_version&.match?(/\A[0-9a-f]{40}\z/)

        latest_version_finder.tag_for_commit_sha(current_version) || current_version
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        fix = security_fix
        return security_updated_requirements(fix) if fix
        return dependency.requirements unless latest_version

        dependency.requirements.map { |requirement| updated_requirement(requirement) }
      end

      private

      sig do
        params(requirement: Dependabot::DependencyRequirement)
          .returns(Dependabot::DependencyRequirement)
      end
      def updated_requirement(requirement)
        source = requirement.source_hash

        if source && registry_dependency?
          # For git dependencies (baselines), update the git ref with the commit SHA
          latest_commit_sha = T.cast(
            latest_version_finder.latest_release_info&.details&.dig("commit_sha"),
            T.nilable(String)
          )
          requirement.source_string("ref")
          updated_source = hash_with_value(source, "ref", latest_commit_sha)
          Dependabot::DependencyRequirement.create(requirement.merge(source: updated_source))
        elsif source.nil? && requirement.requirement
          # For port dependencies (no source but has requirement), update the version constraint
          Dependabot::DependencyRequirement.create(requirement.merge(requirement: ">=#{latest_version}"))
        else
          # Keep the original requirement unchanged for other cases
          requirement
        end
      end

      # Describes the manifest edit that fixes the advisory, so the file updater can apply it
      # without repeating the resolution.
      sig do
        params(fix: SecurityFixResolver::Fix)
          .returns(T::Array[Dependabot::DependencyRequirement])
      end
      def security_updated_requirements(fix)
        dependency.requirements.map do |requirement|
          metadata = T.let(
            requirement.metadata || {},
            Dependabot::DependencyRequirement::ObjectHash
          )
          metadata = hash_with_value(metadata, "security_remediation", fix.kind)
          metadata = hash_with_value(metadata, "security_version", fix.version.to_s)
          metadata = hash_with_value(metadata, "baseline_commit_sha", fix.baseline_commit_sha)
          metadata = hash_with_value(metadata, "baseline_tag", fix.baseline_tag)

          updated = Dependabot::DependencyRequirement.create(requirement.merge(metadata: metadata))
          next updated unless fix.kind == :version_constraint

          Dependabot::DependencyRequirement.create(updated.merge(requirement: ">=#{fix.version}"))
        end
      end

      sig do
        params(
          details: Dependabot::DependencyRequirement::ObjectHash,
          key: String,
          value: Object
        ).returns(Dependabot::DependencyRequirement::ObjectHash)
      end
      def hash_with_value(details, key, value)
        updated = details.dup
        actual_key = if details.key?(key.to_sym)
                       key.to_sym
                     elsif details.key?(key)
                       key
                     elsif details.empty? || details.keys.any?(Symbol)
                       key.to_sym
                     else
                       key
                     end
        updated[actual_key] = value
        updated
      end

      sig { returns(T.nilable(SecurityFixResolver::Fix)) }
      def security_fix
        return @security_fix if @searched_for_security_fix

        @searched_for_security_fix = T.let(true, T.nilable(T::Boolean))
        return nil if registry_dependency?
        return nil unless vulnerable?

        @security_fix = T.let(
          SecurityFixResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            security_advisories: security_advisories,
            ignored_versions: ignored_versions,
            lowest_comparable_version: latest_version_finder.lowest_security_fix_version,
            versions_database: versions_database
          ).fix,
          T.nilable(SecurityFixResolver::Fix)
        )
      end

      sig { returns(T::Boolean) }
      def registry_dependency?
        dependency.source_string("type", allowed_types: ["git"]) == "git"
      end

      sig { returns(T::Boolean) }
      def port_dependency?
        # A port dependency has no git source but has a requirement constraint
        !registry_dependency? && dependency.requirements.any?(&:requirement)
      end

      # A port whose version comes solely from the registry baseline.
      sig { returns(T::Boolean) }
      def baseline_governed?
        return false if registry_dependency?
        return false unless dependency.numeric_version

        dependency.requirements.none?(&:requirement)
      end

      # `latest_version` may be a version vcpkg cannot order against the current one, which is
      # exactly when the override remediation applies. The base class's numeric comparison would
      # then wrongly report the dependency as current, so defer to the resolver: it has already
      # established that the current version is vulnerable and the fix is not.
      sig { returns(T::Boolean) }
      def numeric_version_up_to_date?
        return false if security_fix

        super
      end

      sig { returns(T::Boolean) }
      def preferred_version_resolvable_with_unlock?
        return true if security_fix

        super
      end

      # `latest_version` is a git tag but the baseline is a commit SHA, so the base check never
      # matches and reports an up-to-date baseline as stale. Match the release commit SHA by prefix.
      sig { returns(T::Boolean) }
      def sha1_version_up_to_date?
        return super unless registry_dependency?

        latest_commit_sha = T.cast(
          latest_version_finder.latest_release_info&.details&.dig("commit_sha"),
          T.nilable(String)
        )
        return super unless latest_commit_sha

        latest_commit_sha.start_with?(T.must(dependency.version))
      end

      # Vcpkg doesn't support full unlocking since dependencies are tracked via baselines
      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock? = false

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError, "Vcpkg doesn't support full unlock operations"
      end

      sig { returns(Dependabot::Vcpkg::Package::VersionsDatabase) }
      def versions_database
        @versions_database ||= T.let(
          Dependabot::Vcpkg::Package::VersionsDatabase.new,
          T.nilable(Dependabot::Vcpkg::Package::VersionsDatabase)
        )
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
            raise_on_ignored: raise_on_ignored,
            options: options
          ),
          T.nilable(LatestVersionFinder)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("vcpkg", Dependabot::Vcpkg::UpdateChecker)
