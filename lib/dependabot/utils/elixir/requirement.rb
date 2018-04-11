# frozen_string_literal: true

require "dependabot/utils/elixir/version"

# rubocop:disable all
module Dependabot
  module Utils
    module Elixir
      class Requirement < Gem::Requirement
        OPS["=="] = lambda { |v, r| v == r }

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
        def self.parse obj
          return ["=", obj] if Gem::Version === obj

          unless PATTERN =~ obj.to_s
            raise BadRequirementError, "Illformed requirement [#{obj.inspect}]"
          end

          if $1 == ">=" && $2 == "0"
            DefaultRequirement
          else
            [$1 || "=", Utils::Elixir::Version.new($2)]
          end
        end

        def satisfied_by?(version)
          version = Utils::Elixir::Version.new(version.to_s)
          super
        end
      end
    end
  end
end
# rubocop:enable all
