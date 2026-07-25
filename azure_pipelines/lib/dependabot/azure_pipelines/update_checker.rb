# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

require "dependabot/azure_pipelines/version"

module Dependabot
  module AzurePipelines
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        latest_version_finder.latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        updated = dependency.requirements.map do |requirement|
          {
            file: requirement.file,
            requirement: updated_requirement(requirement.requirement),
            groups: requirement.groups,
            source: requirement.source
          }
        end

        wrap_requirements(updated)
      end

      private

      # Two files can pin the same task at different precision, and merging them into
      # one dependency must not quietly rewrite `Maven@4` as `Maven@4.276.0`. Each
      # requirement is rendered at the precision it was written with.
      sig do
        params(current: T.nilable(Dependabot::DependencyRequirement::Requirement))
          .returns(T.nilable(Dependabot::DependencyRequirement::Requirement))
      end
      def updated_requirement(current)
        latest = latest_version
        return current unless latest
        return latest.to_s unless current.is_a?(String) && Version.correct?(current)

        Version.new(latest.to_s).truncate(Version.new(current).precision).to_s
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
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
    end
  end
end

Dependabot::UpdateCheckers.register("azure_pipelines", Dependabot::AzurePipelines::UpdateChecker)
