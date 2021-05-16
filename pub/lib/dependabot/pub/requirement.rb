# frozen_string_literal: true

# TODO: File and specs need to be updated

require "dependabot/utils"
require "dependabot/pub/version"

# Override all essential methods to make it possible to delegate all work to the
# dedicated Dart library for parsing and updating Dart version constraints.
module Dependabot
  module Pub
    class Requirement < Gem::Requirement
      def initialize(requirements)
        @requirements = requirements.to_s
      end

      def self.parse(obj)
        obj.to_s
      end

      # For consistency with other langauges, we define a requirements array.
      # Pub doesn't have an `OR` separator for requirements, so it
      # always contains a single element.
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end
    end
  end
end

Dependabot::Utils.
  register_requirement_class("pub", Dependabot::Pub::Requirement)
