# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/hex/version"

module Dependabot
  module Hex
    class Requirement < Dependabot::Requirement
      extend T::Sig

      AND_SEPARATOR = /\s+and\s+/
      OR_SEPARATOR = /\s+or\s+/

      # Add the double-equality matcher to the list of allowed operations
      OPS = T.let(
        OPS.merge("==" => lambda { |v, r|
          v == r
        }),
        T::Hash[String, T.proc.params(arg0: Gem::Version, arg1: Gem::Version).returns(T::Boolean)]
      )

      # Override the version pattern to allow local versions
      quoted = OPS.keys.map { |k| Regexp.quote k }.join("|")
      PATTERN_RAW = T.let("\\s*(#{quoted})?\\s*(#{Hex::Version::VERSION_PATTERN})\\s*".freeze, String)
      PATTERN = /\A#{PATTERN_RAW}\z/

      # Returns an array of requirements. At least one requirement from the
      # returned array must be satisfied for a version to be valid.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        T.must(requirement_string).strip.split(OR_SEPARATOR).map do |req_string|
          requirements = req_string.strip.split(AND_SEPARATOR)
          new(requirements)
        end
      end

      # Patches Gem::Requirement to make it accept requirement strings like
      # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
      sig { params(requirements: T.any(String, T::Array[String])).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string.split(",").map(&:strip)
        end

        super(requirements)
      end

      # Override the parser to create Hex::Versions
      sig do
        params(obj: T.any(String, Gem::Version))
          .returns(T::Array[T.any(String, Gem::Version)])
      end
      def self.parse(obj)
        return ["=", Hex::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Hex::Version.new(T.must(matches[2]))]
      end

      sig { params(version: T.any(String, Gem::Version, Dependabot::Version)).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Hex::Version.new(version.to_s)

        requirements.all? { |op, rv| T.must(OPS[op] || OPS["="]).call(version, rv) }
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("hex", Dependabot::Hex::Requirement)
