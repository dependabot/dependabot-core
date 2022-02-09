# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  module GitSubmodules
    class Requirement < Gem::Requirement
      # For consistency with other langauges, we define a requirements array.
      # Ruby doesn't have an `OR` separator for requirements, so it always
      # contains a single element.
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      # Patches Gem::Requirement to make it accept requirement strings like
      # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string.split(",").map(&:strip)
        end

        super(requirements)
      end
    end
  end
end

Dependabot::Utils.
  register_requirement_class("submodules",
                             Dependabot::GitSubmodules::Requirement)
