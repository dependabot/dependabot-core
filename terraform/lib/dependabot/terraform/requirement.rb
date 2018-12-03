# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/terraform/version"

# Just ensures that Terraform requirements use Terraform versions
module Dependabot
  module Terraform
    class Requirement < Gem::Requirement
      def self.parse(obj)
        if obj.is_a?(Gem::Version)
          return ["=", Version.new(obj.to_s)]
        end

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Terraform::Version.new(matches[2])]
      end

      # For consistency with other langauges, we define a requirements array.
      # Terraform doesn't have an `OR` separator for requirements, so it
      # always contains a single element.
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end
    end
  end
end

Dependabot::Utils.
  register_requirement_class("terraform", Dependabot::Terraform::Requirement)
