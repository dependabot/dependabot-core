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
      min_constraints = requirements.select { |op, _| MINIMUM_OPERATORS.include?(op) }
      min_constraint = min_constraints.min_by { |_, version| version }
      min_constraint&.last
    end

    # Returns the maximum version based on the requirement constraints
    sig { returns(T.nilable(Gem::Version)) }
    def max_version
      max_constraints = requirements.select { |op, _| MAXIMUM_OPERATORS.include?(op) }
      max_versions = max_constraints.map do |op, version|
        op == "~>" ? version.bump : version
      end
      max_versions.max
    end
  end
end
