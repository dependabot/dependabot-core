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

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(fetch_latest_version, T.nilable(Gem::Version))
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version # TODO
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dependency.requirements.map do |requirement|
          required_version = T.cast(version_class.new(requirement[:requirement]), Dependabot::Devcontainers::Version)
          updated_requirement = remove_precision_changes(viable_candidates, required_version).last

          {
            file: requirement[:file],
            requirement: updated_requirement,
            groups: requirement[:groups],
            source: requirement[:source]
          }
        end
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      private

      sig { returns(T::Array[Dependabot::Devcontainers::Version]) }
      def viable_candidates
        @viable_candidates ||= T.let(
          fetch_viable_candidates,
          T.nilable(T::Array[Dependabot::Devcontainers::Version])
        )
      end

      sig { returns(T::Array[Dependabot::Devcontainers::Version]) }
      def fetch_viable_candidates
        candidates = comparable_versions_from_registry
        candidates = filter_ignored(candidates)
        candidates.sort
      end

      sig { returns(Dependabot::Devcontainers::Version) }
      def fetch_latest_version
        return T.cast(current_version, Dependabot::Devcontainers::Version) unless viable_candidates.any?

        T.must(viable_candidates.last)
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

      sig do
        params(
          versions: T::Array[Dependabot::Devcontainers::Version]
        )
          .returns(T::Array[Dependabot::Devcontainers::Version])
      end
      def filter_ignored(versions)
        filtered =
          versions.reject do |version|
            ignore_requirements.any? { |r| version.satisfies?(r) }
          end

        if raise_on_ignored &&
           filter_lower_versions(filtered).empty? &&
           filter_lower_versions(versions).any?
          raise AllVersionsIgnored
        end

        filtered
      end

      sig { returns(T::Array[Dependabot::Devcontainers::Version]) }
      def comparable_versions_from_registry
        tags_from_registry.filter_map do |tag|
          version_class.correct?(tag) && T.cast(version_class.new(tag), Dependabot::Devcontainers::Version)
        end
      end

      sig { returns(T::Array[String]) }
      def tags_from_registry
        @tags_from_registry ||= T.let(fetch_tags_from_registry, T.nilable(T::Array[String]))
      end

      sig { returns(T::Array[String]) }
      def fetch_tags_from_registry
        cmd = "devcontainer features info tags #{dependency.name} --output-format json"

        Dependabot.logger.info("Running command: `#{cmd}`")

        output = SharedHelpers.run_shell_command(cmd, stderr_to_stdout: false)

        JSON.parse(output).fetch("publishedTags")
      end

      sig { params(versions: T::Array[Gem::Version]).returns(T::Array[Gem::Version]) }
      def filter_lower_versions(versions)
        versions.select do |version|
          version > current_version
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
