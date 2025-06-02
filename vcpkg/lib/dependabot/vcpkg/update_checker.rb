# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Vcpkg
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        @latest_version ||= T.let(
          latest_version_finder.latest_tag,
          T.nilable(T.any(String, Dependabot::Version))
        )
      end

      # Vcpkg baselines don't have resolvability issues since we're dealing with
      # git tags from the official repository, so these methods delegate to latest_version
      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version = latest_version

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock = latest_version

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return dependency.requirements unless latest_version

        dependency.requirements.filter_map do |requirement|
          source = T.cast(requirement[:source], T.nilable(T::Hash[Symbol, T.untyped]))

          if source
            requirement.merge(source: source.merge(ref: latest_version.to_s))
          else
            requirement
          end
        end
      end

      private

      # Vcpkg doesn't support full unlocking since dependencies are tracked via baselines
      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock? = false

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError, "Vcpkg doesn't support full unlock operations"
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
