# frozen_string_literal: true

require "dependabot/utils/elm/version"

module Dependabot
  module Utils
    module Elm
      class Requirement < Gem::Requirement
        # Override the version pattern to allow local versions
        PATTERN_RAW =
          "(#{Utils::Elm::Version::VERSION_PATTERN}) (<=?) v (<=?) " \
          "(#{Utils::Elm::Version::VERSION_PATTERN})"
        PATTERN = /\A#{PATTERN_RAW}\z/

        # Returns an array of requirements. At least one requirement from the
        # returned array must be satisfied for a version to be valid.
        def self.requirements_array(requirement_string)
          [new(requirement_string)]
        end

        def initialize(*requirements)
          if requirements.any?(&:nil?)
            raise BadRequirementError, "Nil requirement not supported in Elm"
          end
          super
        end

        # Override the parser to create Utils::Elm::Versions
        def self.parse(obj)
          if obj.is_a?(Gem::Version)
            version = Utils::Elm::Version.new(obj.to_s)
            return ["=", version]
          end

          matches = PATTERN.match(obj.to_s)
          if !matches || !obj
            msg = "Illformed requirement #{obj.inspect}"
            raise BadRequirementError, msg
          end

          # Elm requriements are either a <= v <= b
          # or a <= v < b. Since we're not downgrading
          # we can simplify to Ruby's `=` and `<`.
          if matches[1] == matches[4]
            ["=", Utils::Elm::Version.new(matches[1])]
          else
            ["<", Utils::Elm::Version.new(matches[4])]
          end
        end

        def satisfied_by?(version)
          version = Utils::Elm::Version.new(version.to_s)
          super
        end
      end
    end
  end
end
