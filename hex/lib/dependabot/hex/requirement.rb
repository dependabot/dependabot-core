# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/hex/version"

module Dependabot
  module Hex
    class Requirement < Gem::Requirement
      extend T::Sig

      AND_SEPARATOR = /\s+and\s+/
      OR_SEPARATOR = /\s+or\s+/

      # Add the double-equality matcher to the list of allowed operations
      OPS = T.let(
        OPS.merge("==" => ->(v, r) { v == r }),
        T::Hash[String, T.proc.params(v: Hex::Version, r: Hex::Version).returns(T::Boolean)]
      )

      # Override the version pattern to allow local versions
      quoted = OPS.keys.map { |k| Regexp.quote k }.join "|"
      PATTERN_RAW = T.let("\\s*(#{quoted})?\\s*(#{Hex::Version::VERSION_PATTERN})\\s*".freeze, String)
      PATTERN = /\A#{PATTERN_RAW}\z/

      # Returns an array of requirements. At least one requirement from the
      # returned array must be satisfied for a version to be valid.
      sig { params(requirement_string: String).returns(T::Array[Dependabot::Hex::Requirement]) }
      def self.requirements_array(requirement_string)
        requirement_string.strip.split(OR_SEPARATOR).map do |req_string|
          requirements = req_string.strip.split(AND_SEPARATOR)
          new(T.unsafe(requirements))
        end
      end

      # Patches Gem::Requirement to make it accept requirement strings like
      # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
      sig { override.params(requirements: String).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string.split(",").map(&:strip)
        end

        super(requirements)
      end

      # Override the parser to create Hex::Versions
      sig { override.params(obj: Object).returns([String, Dependabot::Hex::Version]) }
      def self.parse(obj)
        return ["=", Hex::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Hex::Version.new(matches[2])]
      end

      sig { override.params(version: T.any(String, Dependabot::Hex::Version)).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Hex::Version.new(version.to_s)

        requirements.all? { |op, rv| T.unsafe(OPS[op] || OPS["="]).call(version, rv) }
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("hex", Dependabot::Hex::Requirement)
