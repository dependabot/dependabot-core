# frozen_string_literal: true

require "dependabot/utils/elixir/version"

module Dependabot
  module Utils
    module Elixir
      class Requirement < Gem::Requirement
        OPS["=="] = ->(v, r) { v == r }

        # Override the version pattern to allow local versions
        quoted = OPS.keys.map { |k| Regexp.quote k }.join "|"
        PATTERN_RAW =
          "\\s*(#{quoted})?\\s*(#{Utils::Elixir::Version::VERSION_PATTERN})\\s*"
        PATTERN = /\A#{PATTERN_RAW}\z/

        # For consistency with other langauges, we define a requirements array.
        # Elixir doesn't have an `OR` separator for requirements, so it always
        # contains a single element.
        def self.requirements_array(requirement_string)
          [new(requirement_string)]
        end

        # Override the parser to create Utils::Elixir::Versions
        def self.parse(obj)
          if obj.is_a?(Gem::Version)
            return ["=", Utils::Elixir::Version.new(obj.to_s)]
          end

          unless (matches = PATTERN.match(obj.to_s))
            msg = "Illformed requirement [#{obj.inspect}]"
            raise BadRequirementError, msg
          end

          return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"
          [matches[1] || "=", Utils::Elixir::Version.new(matches[2])]
        end

        def satisfied_by?(version)
          version = Utils::Elixir::Version.new(version.to_s)
          super
        end
      end
    end
  end
end
