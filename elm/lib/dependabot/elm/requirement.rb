# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/elm/version"

module Dependabot
  module Elm
    class Requirement < Gem::Requirement
      ELM_PATTERN_RAW =
        "(#{Elm::Version::VERSION_PATTERN}) (<=?) v (<=?) " \
        "(#{Elm::Version::VERSION_PATTERN})"
      ELM_PATTERN = /\A#{ELM_PATTERN_RAW}\z/.freeze
      ELM_EXACT_PATTERN = /\A#{Elm::Version::VERSION_PATTERN}\z/.freeze

      # Returns an array of requirements. At least one requirement from the
      # returned array must be satisfied for a version to be valid.
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          if req_string.nil?
            raise BadRequirementError, "Nil requirement not supported in Elm"
          end

          req_string.split(",").map do |r|
            convert_elm_constraint_to_ruby_constraint(r)
          end
        end

        super(requirements)
      end

      def satisfied_by?(version)
        version = Elm::Version.new(version.to_s)
        super
      end

      private

      # Override the parser to create Elm::Versions and return an
      # array of parsed requirements
      def convert_elm_constraint_to_ruby_constraint(obj)
        # If a version is given this is an equals requirement
        return obj if ELM_EXACT_PATTERN.match?(obj.to_s)

        return obj unless (matches = ELM_PATTERN.match(obj.to_s))

        # If the two versions specified are identical this is an equals
        # requirement
        return matches[4] if matches[1] == matches[4] && matches[3] == "<="

        [
          [matches[2].tr("<", ">"), matches[1]].join(" "),
          [matches[3], matches[4]].join(" ")
        ]
      end
    end
  end
end

Dependabot::Utils.
  register_requirement_class("elm", Dependabot::Elm::Requirement)
