# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/devcontainers/version"
require "dependabot/update_checkers/version_filters"
require "dependabot/devcontainers/requirement"

module Dependabot
  module Devcontainers
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(T.must(release_versions).last, T.nilable(Gem::Version))
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version # TODO
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dependency.requirements.map do |requirement|
          required_version = T.cast(version_class.new(requirement[:requirement]), Dependabot::Devcontainers::Version)
          updated_requirement = remove_precision_changes(
            T.cast(release_versions, T::Array[Dependabot::Devcontainers::Version]),
            required_version
          ).last
          {
            file: requirement[:file],
            requirement: updated_requirement,
            groups: requirement[:groups],
            source: requirement[:source]
          }
        end
      end

      private

      sig { returns(T.nilable(Dependabot::Devcontainers::UpdateChecker::LatestVersionFinder)) }
      def latest_version_finder
        @latest_version_finder ||= T.let(LatestVersionFinder.new(
                                           dependency: dependency,
                                           credentials: credentials,
                                           dependency_files: dependency_files,
                                           security_advisories: security_advisories,
                                           ignored_versions: ignored_versions,
                                           raise_on_ignored: raise_on_ignored,
                                           cooldown_options: update_cooldown
                                         ),
                                         T.nilable(Dependabot::Devcontainers::UpdateChecker::LatestVersionFinder))
      end

      sig { returns(T.nilable(T::Array[Dependabot::Version])) }
      def release_versions
        @release_versions ||= T.let(
          T.must(T.must(latest_version_finder).release_versions),
          T.nilable(T::Array[Dependabot::Version])
        )
      end

      sig do
        params(
          versions: T::Array[Dependabot::Devcontainers::Version],
          required_version: Dependabot::Devcontainers::Version
        )
          .returns(T::Array[Dependabot::Devcontainers::Version])
      end
      def remove_precision_changes(versions, required_version)
        versions.select do |version|
          version.same_precision?(required_version)
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false # TODO
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end
    end
  end
end

Dependabot::UpdateCheckers.register("devcontainers", Dependabot::Devcontainers::UpdateChecker)
