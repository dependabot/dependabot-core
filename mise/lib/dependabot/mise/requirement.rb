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

        super(requirements.reject { |r| r.match?(WILDCARD_PATTERN) })
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        result = @wildcard_patterns.all? { |pattern| WildcardMatcher.match?(pattern, version.to_s) } && super
        T.cast(result, T::Boolean)
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("mise", Dependabot::Mise::Requirement)
