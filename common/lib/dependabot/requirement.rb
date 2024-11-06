# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Requirement < Gem::Requirement
    extend T::Sig
    extend T::Helpers

    # Constants for operator groups
    MINIMUM_OPERATORS = %w(>= >).freeze
    MAXIMUM_OPERATORS = %w(<= < ~>).freeze

    abstract!

    # Parses requirement strings and returns an array of requirement objects.
    sig do
      abstract
        .params(requirement_string: T.nilable(String))
        .returns(T::Array[Requirement])
    end
    def self.requirements_array(requirement_string); end

    # Returns all requirement constraints as an array of strings
    sig { returns(T::Array[String]) }
    def constraints
      requirements.map { |op, version| "#{op} #{version}" }
    end

    # Returns the minimum version based on the requirement constraints
    sig { returns(T.nilable(Gem::Version)) }
    def min_version
      # Select constraints with minimum operators
      min_constraints = requirements.select { |op, _| MINIMUM_OPERATORS.include?(op) }

      # Choose the maximum version among the minimum constraints
      max_min_constraint = min_constraints.max_by { |_, version| version }

      # Return the version part of the max constraint, if it exists
      max_min_constraint&.last
    end

    # Returns the maximum version based on the requirement constraints
    sig { returns(T.nilable(Gem::Version)) }
    def max_version
      # Select constraints with maximum operators
      max_constraints = requirements.select { |op, _| MAXIMUM_OPERATORS.include?(op) }

      # Map each constraint to its effective upper bound, calculating for `~>`
      min_max_constraint = max_constraints.min_by do |op, version|
        op == "~>" ? version.bump : version
      end

      # Return the smallest maximum constraint, if it exists
      min_max_constraint&.last
    end
  end
end
