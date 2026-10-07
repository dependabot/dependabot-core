# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    class Requirement < Dependabot::Requirement
      extend T::Sig

      # `Gem::Requirement::OPS` lists `>` before `>=`, which would make the shorter operator win
      # against vcpkg's permissive version syntax. Longest first keeps `>=1.2.3` intact.
      OPERATOR_PATTERN = T.let(
        OPS.keys.sort_by { |op| -op.length }.map { |op| Regexp.quote(op) }.join("|").freeze,
        String
      )

      PATTERN_RAW = T.let(
        "\\s*(#{OPERATOR_PATTERN})?\\s*(#{Version::REQUIREMENT_VERSION_PATTERN.source})\\s*".freeze,
        String
      )
      PATTERN = /\A#{PATTERN_RAW}\z/

      # Vcpkg requirements are a single constraint, but ignore conditions arrive as a
      # comma-separated list.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Dependabot::Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      # Use `Vcpkg::Version` rather than `Gem::Version` so port versions and the string scheme
      # survive requirement parsing.
      sig { params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        return ["=", Vcpkg::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        matches = PATTERN.match(obj.to_s)
        raise BadRequirementError, "Illformed requirement [#{obj.inspect}]" unless matches

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Vcpkg::Version.new(T.must(matches[2]))]
      end

      sig { params(requirements: T.nilable(T.any(String, Gem::Version, T::Array[T.nilable(String)]))).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          next req_string unless req_string.is_a?(String)

          req_string.split(",").map(&:strip).reject(&:empty?)
        end

        super(requirements)
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("vcpkg", Dependabot::Vcpkg::Requirement)
