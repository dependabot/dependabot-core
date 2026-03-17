# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Mise
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories,
            cooldown_options: update_cooldown
          ).latest_version,
          T.nilable(T.any(String, Gem::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(String)) }
      def latest_resolvable_version_with_no_unlock
        # mise has no lockfile; the version pinned in mise.toml IS the resolved version.
        # "No unlock" means staying at the current pin.
        dependency.version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return dependency.requirements if latest_version.nil?

        dependency.requirements.map do |req|
          req.merge(requirement: latest_version.to_s)
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
    end
  end
end

Dependabot::UpdateCheckers.register("mise", Dependabot::Mise::UpdateChecker)

require_relative "update_checker/latest_version_finder"
