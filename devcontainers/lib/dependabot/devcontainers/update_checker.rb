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
        @latest_version ||= dependency.requirements.map do |requirement|
          Version.new(requirement[:metadata][:latest])
        end.max
      end

      def latest_resolvable_version
        latest_version # TODO
      end

      def updated_requirements
        dependency.requirements.map do |requirement|
          latest_version = requirement[:metadata][:latest]
          existing_precision = requirement[:requirement].split(".").size
          updated_requirement = latest_version.split(".")[0...existing_precision].join(".")

          {
            file: requirement[:file],
            requirement: updated_requirement,
            groups: requirement[:groups],
            source: requirement[:source],
            metadata: requirement[:metadata]
          }
        end
      end

      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      private

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
