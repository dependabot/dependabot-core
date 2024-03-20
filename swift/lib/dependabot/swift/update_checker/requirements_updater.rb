# typed: true
# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/swift/native_requirement"
require "dependabot/swift/version"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        def initialize(requirements:, target_version:)
          @requirements = requirements

          return unless target_version && Version.correct?(target_version)

          @target_version = Version.new(target_version)
        end

        def updated_requirements
          NativeRequirement.map_requirements(requirements) do |requirement|
            requirement.update_if_needed(target_version)
          end
        end

        private

        attr_reader :requirements
        attr_reader :target_version
      end
    end
  end
end
