# typed: true
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/devcontainers/version"
require "dependabot/update_checkers/version_filters"
require "dependabot/devcontainers/requirement"

module Dependabot
  module Devcontainers
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def latest_version
        @latest_version ||= fetch_latest_version
      end

      def latest_resolvable_version
        latest_version # TODO
      end

      def updated_requirements
        dependency.requirements.map do |requirement|
          required_version = version_class.new(requirement[:requirement])
          updated_requirement = remove_precision_changes(viable_candidates, required_version).last
          updated_metadata = requirement[:metadata].update(latest: latest_version)

          {
            file: requirement[:file],
            requirement: updated_requirement,
            groups: requirement[:groups],
            source: requirement[:source],
            metadata: updated_metadata
          }
        end
      end

      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      private

      def viable_candidates
        @viable_candidates ||= fetch_viable_candidates
      end

      def fetch_viable_candidates
        candidates = comparable_versions_from_registry
        candidates = filter_ignored(candidates)
        candidates.sort
      end

      def fetch_latest_version
        return current_version unless viable_candidates.any?

        viable_candidates.last
      end

      def remove_precision_changes(versions, required_version)
        versions.select do |version|
          version.same_precision?(required_version)
        end
      end

      def filter_ignored(versions)
        filtered =
          versions.reject do |version|
            ignore_requirements.any? { |r| version.satisfies?(r) }
          end

        if @raise_on_ignored &&
           filter_lower_versions(filtered).empty? &&
           filter_lower_versions(versions).any?
          raise AllVersionsIgnored
        end

        filtered
      end

      def comparable_versions_from_registry
        tags_from_registry.filter_map do |tag|
          version_class.correct?(tag) && version_class.new(tag)
        end
      end

      def tags_from_registry
        @tags_from_registry ||= fetch_tags_from_registry
      end

      def fetch_tags_from_registry
        cmd = "devcontainer features info tags #{dependency.name} --output-format json"

        Dependabot.logger.info("Running command: `#{cmd}`")

        output = SharedHelpers.run_shell_command(cmd, stderr_to_stdout: false)

        JSON.parse(output).fetch("publishedTags")
      end

      def filter_lower_versions(versions)
        versions.select do |version|
          version > current_version
        end
      end

      def latest_version_resolvable_with_full_unlock?
        false # TODO
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end
    end
  end
end

Dependabot::UpdateCheckers.register("devcontainers", Dependabot::Devcontainers::UpdateChecker)
