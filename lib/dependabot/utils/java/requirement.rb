# frozen_string_literal: true

module Dependabot
  module Utils
    module Java
      class Requirement < Gem::Requirement
        # For consistency with other langauges, we define a requirements array.
        # Java doesn't have an `OR` separator for requirements, so it always
        # contains a single element.
        def self.requirements_array(requirement_string)
          [new(requirement_string)]
        end
      end
    end
  end
end
