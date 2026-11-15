# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

require "dependabot/nimble/requirements_updater"

module Dependabot
  module Nimble
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        latest_version_finder.latest_version
      end

      # A `requires` string only states which versions are accepted; nothing else has to
      # resolve (there is no lockfile support yet), so the latest version is always the target.
      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
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
        target = preferred_resolvable_version
        return dependency.requirements unless target

        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: version_class.new(target.to_s)
        ).updated_requirements
      end

      private

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

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        []
      end
    end
  end
end

Dependabot::UpdateCheckers.register("nimble", Dependabot::Nimble::UpdateChecker)
