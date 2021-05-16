# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/pub/version"

module Dependabot
  module Pub
    class Requirement < Gem::Requirement
      OPS = {
        "=" => ->(a, b) { a == b },
        ">" => ->(a, b) { a > b },
        ">=" => ->(a, b) { a >= b },
        "<" => ->(a, b) { a < b },
        "<=" => ->(a, b) { a <= b },
        "^" => ->(a, b) { a >= b && a.release < b.breaking },
        "any" => proc { true }
      }.freeze

      # Overwrite Gem::Requirement DefaultRequirement
      DefaultRequirement = [">=", Pub::Version.new("0.0.0")].freeze # rubocop:disable Naming/ConstantName

      COMPARISON_PATTERN = "[<>]=?\\s*#{Pub::Version::VERSION_PATTERN}"
      UNION_PATTERN = "(#{COMPARISON_PATTERN})(\\s*#{COMPARISON_PATTERN})?"
      UNION_REGEX = /\A\s*#{UNION_PATTERN}\s*\Z/.freeze

      REQUIREMENT_PATTERN = "\\s*([<>]=?|\\^)?\\s*(#{Pub::Version::VERSION_PATTERN})\\s*"
      REQUIREMENT_REGEX = /\A#{REQUIREMENT_PATTERN}\Z/.freeze

      def self.parse(obj)
        return ["=", obj] if obj.is_a?(Pub::Version)
        return ["=", Pub::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)
        return DefaultRequirement if obj == ">= 0"
        return ["=", Pub::Version.new(obj.to_s.strip)] if Pub::Version::VERSION_REGEX.match?(obj.to_s.strip)
        return ["any", Pub::Version.new("0.0.0")] if /\Aany\Z/.match?(obj.to_s.strip)

        matches = REQUIREMENT_REGEX.match(obj.to_s)

        raise BadRequirementError unless matches

        [matches[1], Pub::Version.new(matches[2])]
      end

      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      def initialize(*requirements)
        requirements = requirements.flatten.compact.map do |obj|
          next obj unless obj.is_a?(String) && UNION_REGEX.match?(obj)

          obj.scan(UNION_REGEX).flatten.compact
        end

        super(requirements)
      end

      def satisfied_by?(version)
        version = Pub::Version.new(version.to_s)

        @requirements.all? { |op, req_ver| OPS[op].call(version, req_ver) }
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("pub", Dependabot::Pub::Requirement)
