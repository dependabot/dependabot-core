# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_requirement"
require "dependabot/nimble/requirement"
require "dependabot/nimble/version"

module Dependabot
  module Nimble
    # Moves the version a `requires` string starts from up to the latest version.
    #
    #   >= 1.2            becomes  >= 1.5.0
    #   ^= 1.2 / ~= 1.2   becomes  ^= 1.5.0 / ~= 1.5.0
    #   > 1.2             becomes  >= 1.5.0
    #   1.2 / == 1.2      becomes  == 1.5.0 / 1.5.0 (an exact pin follows the release)
    #   >= 1.2 & < 2.0    becomes  >= 1.5.0 & < 2.0, but stays when 2.0 excludes the latest version
    #
    # A package without a version (`requires "foo"`) or with `*` accepts anything and is left alone.
    class RequirementsUpdater
      extend T::Sig

      LOWER = /(?<op>>=|>|==|\^=|~=)?(?<gap>\s*)(?<version>[0-9][0-9A-Za-z.+\-]*)/
      UPPER_OPERATORS = %w(< <=).freeze

      sig do
        params(
          requirements: T::Array[Dependabot::DependencyRequirement],
          latest_version: Dependabot::Version
        ).void
      end
      def initialize(requirements:, latest_version:)
        @requirements = requirements
        @latest_version = latest_version
      end

      sig { returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        @requirements.map do |requirement|
          current = requirement.requirement_string
          updated = current && updated_string(current)
          next requirement if updated.nil? || updated == current

          Dependabot::DependencyRequirement.create(requirement.merge(requirement: updated))
        end
      end

      private

      sig { params(string: String).returns(T.nilable(String)) }
      def updated_string(string)
        parts = string.split(/(&)/)
        return if parts.any? { |part| part != "&" && !upper_bound?(part) && !lower_bound?(part) }
        return if parts.any? { |part| upper_bound?(part) && !upper_bound_allows_latest?(part) }

        parts.map { |part| lower_bound?(part) ? part.sub(LOWER) { replacement(Regexp.last_match) } : part }.join
      end

      sig { params(match: T.nilable(MatchData)).returns(String) }
      def replacement(match)
        return @latest_version.to_s unless match

        operator = match[:op] == ">" ? ">=" : match[:op]
        "#{operator}#{match[:gap]}#{@latest_version}"
      end

      sig { params(part: String).returns(T::Boolean) }
      def lower_bound?(part)
        match = LOWER.match(part.strip)
        !match.nil? && !UPPER_OPERATORS.include?(part.strip[/\A[<>=^~]+/]) && part.strip != "&"
      end

      sig { params(part: String).returns(T::Boolean) }
      def upper_bound?(part)
        UPPER_OPERATORS.include?(part.strip[/\A[<>=^~]+/])
      end

      sig { params(part: String).returns(T::Boolean) }
      def upper_bound_allows_latest?(part)
        Dependabot::Nimble::Requirement.new(part.strip).satisfied_by?(@latest_version)
      end
    end
  end
end
