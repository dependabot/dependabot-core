# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Powershell
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/requirements_updater"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        latest_version_finder.latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # The PowerShell Gallery has no dependency-resolution step of its
        # own (module manifests don't pin transitive dependency versions in
        # a way that requires a native resolver), so the latest version is
        # always resolvable.
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version_with_no_unlock
        latest_version_finder.latest_version_with_no_unlock
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_resolvable_security_fix_version
        lowest_security_fix_version
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        wrap_requirements(
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_resolvable_version: preferred_resolvable_version&.to_s
          ).updated_requirements
        )
      end

      private

      sig { override.returns(T::Boolean) }
      def version_up_to_date?
        return latest_version.to_s == T.must(dependency.version) if exact_pin?

        super
      end

      # The base implementation compares `latest_version` against only the
      # lower bound extracted from the dependency's requirements (see
      # `version_from_requirements`), which incorrectly reports "not up to
      # date" for a versionless bounded range like ">= 1.0.0, <= 5.0.0" as
      # soon as `latest_version` exceeds the lower bound - even though that
      # version is well within the declared range and RequirementsUpdater
      # correctly leaves the requirement unchanged. Overriding here to check
      # whether `latest_version` actually satisfies every declared
      # requirement keeps `up_to_date?`/`can_update?` consistent with what
      # RequirementsUpdater decides.
      sig { override.returns(T::Boolean) }
      def requirements_up_to_date?
        return false unless latest_version

        latest = version_class.new(latest_version.to_s)

        dependency.requirements.all? do |r|
          requirement_string = T.cast(r.fetch(:requirement), T.nilable(String))

          requirement_class.requirements_array(requirement_string)
                           .all? { |requirement| requirement.satisfied_by?(latest) }
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock (updating other dependencies to help this one update)
        # isn't supported for PowerShell modules.
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
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
            raise_on_ignored: raise_on_ignored
          ),
          T.nilable(LatestVersionFinder)
        )
      end

      sig { returns(T::Boolean) }
      def exact_pin?
        dependency.requirements.any? do |requirement|
          requirement.metadata&.fetch(:version_key, nil) == "RequiredVersion"
        end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("powershell", Dependabot::Powershell::UpdateChecker)
