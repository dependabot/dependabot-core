# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/julia/registry_client"
require "dependabot/julia/requirement"

module Dependabot
  module Julia
    # Load helper classes
    autoload :LatestVersionFinder, "dependabot/julia/update_checker/latest_version_finder"
    autoload :RequirementsUpdater, "dependabot/julia/update_checker/requirements_updater"

    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      sig { override.returns(T.nilable(Gem::Version)) }
      def latest_version
        @latest_version ||= T.let(latest_version_finder.latest_version, T.nilable(Gem::Version))
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def latest_resolvable_version
        # For Julia, the latest version is generally resolvable since
        # the manifest file locks exact versions, so we use latest_version
        @latest_resolvable_version ||= T.let(latest_version, T.nilable(Gem::Version))
      end

      sig { override.returns(T.nilable(T.any(Dependabot::Version, String))) }
      def latest_resolvable_version_with_no_unlock
        # Return latest version that satisfies current requirement constraints
        return nil unless latest_version

        current_requirement = T.cast(dependency.requirements.first&.fetch(:requirement, nil), T.nilable(String))

        if current_requirement.nil? || current_requirement == "*"
          return Dependabot::Julia::Version.new(latest_version.to_s)
        end

        req = requirement_class.new(current_requirement)
        return unless T.cast(req.satisfied_by?(latest_version), T::Boolean)

        Dependabot::Julia::Version.new(latest_version.to_s)
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        Dependabot::Julia::RequirementsUpdater.new(
          requirements: dependency.requirements,
          target_version: latest_resolvable_version&.to_s,
          update_strategy: requirements_update_strategy&.to_s&.to_sym
        ).updated_requirements
      end

      private

      sig { returns(Dependabot::Julia::LatestVersionFinder) }
      def latest_version_finder
        @latest_version_finder ||= T.let(Dependabot::Julia::LatestVersionFinder.new(
                                           dependency: dependency,
                                           dependency_files: dependency_files,
                                           credentials: credentials,
                                           ignored_versions: ignored_versions,
                                           security_advisories: security_advisories,
                                           raise_on_ignored: raise_on_ignored,
                                           cooldown_config: cooldown_config
                                         ), T.nilable(Dependabot::Julia::LatestVersionFinder))
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def cooldown_config
        return nil unless update_cooldown

        # Convert the ReleaseCooldownOptions to a hash for compatibility
        {
          default_days: update_cooldown.default_days,
          semver_major_days: update_cooldown.semver_major_days,
          semver_minor_days: update_cooldown.semver_minor_days,
          semver_patch_days: update_cooldown.semver_patch_days,
          include: update_cooldown.include,
          exclude: update_cooldown.exclude
        }
      end

      sig { returns(T.class_of(Dependabot::Julia::Requirement)) }
      def requirement_class
        Dependabot::Julia::Requirement
      end
    end
  end
end

Dependabot::UpdateCheckers.register("julia", Dependabot::Julia::UpdateChecker)
