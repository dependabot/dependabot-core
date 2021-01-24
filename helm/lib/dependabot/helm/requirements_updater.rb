# frozen_string_literal: true

require "dependabot/helm/version"
require "dependabot/helm/requirement"

module Dependabot
  module Helm
    class RequirementsUpdater
      def initialize(requirements:, latest_version:)
        @requirements = requirements

        return unless latest_version
        return unless version_class.correct?(latest_version)

        @latest_version = version_class.new(latest_version)
      end

      def updated_requirements
        return requirements unless latest_version

        # NOTE: Order is important here. The FileUpdater needs the updated
        # requirement at index `i` to correspond to the previous requirement
        # at the same index.
        requirements.map do |req|
          update_requirement(req)
        end
      end

      private

      attr_reader :requirements, :latest_version

      def update_requirement(req)
        return req if req.fetch(:requirement).nil?

        req.merge(requirement: latest_version.to_s)
      end

      def version_class
        Version
      end

      def requirement_class
        Requirement
      end
    end
  end
end
