# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/lean"
require "dependabot/lean/lake/update_checker"

module Dependabot
  module Lean
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        return lake_update_checker.latest_version if lake_package?

        latest_version_finder.latest_version&.to_s
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        return lake_update_checker.latest_resolvable_version if lake_package?

        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version_with_no_unlock
        return lake_update_checker.latest_resolvable_version_with_no_unlock if lake_package?

        latest_version
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_security_fix_version
        return nil if lake_package?

        latest_version_finder.lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_resolvable_security_fix_version
        lowest_security_fix_version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return lake_update_checker.updated_requirements if lake_package?
        return dependency.requirements if latest_version.nil?

        dependency.requirements.map do |req|
          req.merge(requirement: latest_version)
        end
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

      sig { returns(T::Boolean) }
      def lake_package?
        source_details = dependency.source_details
        return false unless source_details

        source_details[:type] == "git"
      end

      sig { returns(Lake::UpdateChecker) }
      def lake_update_checker
        @lake_update_checker ||= T.let(
          Lake::UpdateChecker.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            raise_on_ignored: raise_on_ignored
          ),
          T.nilable(Lake::UpdateChecker)
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
            raise_on_ignored: raise_on_ignored
          ),
          T.nilable(LatestVersionFinder)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("lean", Dependabot::Lean::UpdateChecker)
