# frozen_string_literal: true

require "dependabot/utils/dotnet/version"

module Dependabot
  module Utils
    module Dotnet
      class Requirement < Gem::Requirement
        def self.parse(obj)
          if obj.is_a?(Gem::Version)
            return ["=", Utils::Dotnet::Version.new(obj.to_s)]
          end

          unless (matches = PATTERN.match(obj.to_s))
            msg = "Illformed requirement [#{obj.inspect}]"
            raise BadRequirementError, msg
          end

          return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"
          [matches[1] || "=", Utils::Dotnet::Version.new(matches[2])]
        end

        # For consistency with other langauges, we define a requirements array.
        # Dotnet doesn't have an `OR` separator for requirements, so it always
        # contains a single element.
        def self.requirements_array(requirement_string)
          [new(requirement_string)]
        end

        def satisfied_by?(version)
          version = Utils::Dotnet::Version.new(version.to_s)
          super
        end
      end
    end
  end
end
