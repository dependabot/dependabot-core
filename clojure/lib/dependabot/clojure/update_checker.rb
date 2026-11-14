# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Clojure
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_finder"

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_version
        latest_version_details&.fetch(:version)
      end

      # Versions are pinned in the manifest and there is no lockfile, so any
      # published version can be used.
      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        lowest_security_fix_version_details&.fetch(:version)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        nil
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version&.to_s,
          source_url: preferred_version_details&.fetch(:source_url)
        ).updated_requirements
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        []
      end

      sig { override.returns(T::Boolean) }
      def numeric_version_up_to_date?
        return false unless version_class.correct?(dependency.version)

        super
      end

      sig { override.params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def numeric_version_can_update?(requirements_to_unlock:)
        return false unless version_class.correct?(dependency.version)

        super
      end

      sig { returns(T.nilable(Maven::Shared::BaseVersionFinder::VersionDetails)) }
      def preferred_version_details
        return lowest_security_fix_version_details if vulnerable?

        latest_version_details
      end

      sig { returns(T.nilable(Maven::Shared::BaseVersionFinder::VersionDetails)) }
      def latest_version_details
        version_finder.latest_version_details
      end

      sig { returns(T.nilable(Maven::Shared::BaseVersionFinder::VersionDetails)) }
      def lowest_security_fix_version_details
        version_finder.lowest_security_fix_version_details
      end

      sig { returns(VersionFinder) }
      def version_finder
        @version_finder ||= T.let(
          VersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            cooldown_options: update_cooldown,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          ),
          T.nilable(VersionFinder)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("clojure", Dependabot::Clojure::UpdateChecker)
