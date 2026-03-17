# typed: strong
# frozen_string_literal: true

require "dependabot/requirement"
require "dependabot/utils"
require "wildcard_matcher"

module Dependabot
  module Mise
    class Requirement < Dependabot::Requirement
      extend T::Sig

      WILDCARD_PATTERN = /\*/

      sig do
        override
          .params(requirement_string: T.nilable(String))
          .returns(T::Array[Requirement])
      end
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig { params(requirements: T.nilable(String)).void }
      def initialize(*requirements)
        requirements = requirements.flatten.compact.flat_map { |r| r.split(",").map(&:strip) }

        @wildcard_patterns = T.let(
          requirements.select { |r| r.match?(WILDCARD_PATTERN) },
          T::Array[String]
        )

        normal = requirements.reject { |r| r.match?(WILDCARD_PATTERN) }
        # When all patterns are wildcards, pass a placeholder requirement so that
        # Gem::Requirement doesn't fall back to a catch-all ">= 0". satisfied_by?
        # only delegates to super when there are no wildcard patterns, so this
        # placeholder is never evaluated for wildcard-only requirements.
        super(normal.empty? ? ["!= 0"] : normal)
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        version_string = version.to_s
        result = @wildcard_patterns.any? { |p| WildcardMatcher.match?(p, version_string) } ||
                 (@wildcard_patterns.empty? && super)
        T.cast(result, T::Boolean)
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("mise", Dependabot::Mise::Requirement)
