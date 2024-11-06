# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Requirement < Gem::Requirement
    extend T::Sig
    extend T::Helpers

    # Constants for operator groups
    MINIMUM_OPERATORS = %w(>= > ~>).freeze
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

    # Returns the highest lower limit among all minimum constraints.
    sig { returns(T.nilable(Gem::Version)) }
    def min_version
      # Select constraints with minimum operators
      min_constraints = requirements.select { |op, _| MINIMUM_OPERATORS.include?(op) }

      # Choose the maximum version among the minimum constraints
      max_min_constraint = min_constraints.max_by { |_, version| version }

      # Return the version part of the max constraint, if it exists
      Dependabot::Version.new(max_min_constraint&.last) if max_min_constraint&.last
    end

    # Returns the lowest upper limit among all maximum constraints.
    sig { returns(T.nilable(Dependabot::Version)) }
    def max_version
      # Select constraints with maximum operators
      max_constraints = requirements.select { |op, _| MAXIMUM_OPERATORS.include?(op) }

      # Process each maximum constraint, handling "~>" constraints based on length
      effective_max_versions = max_constraints.map do |op, version|
        if op == "~>"
          # If "~>" constraint, bump based on the specificity of the version
          case version.segments.length
          when 1
            # Bump major version (e.g., 2 -> 3.0.0)
            Dependabot::Version.new((version.segments[0].to_i + 1).to_s + ".0.0")
          when 2
            # Bump minor version (e.g., 2.5 -> 2.6.0)
            Dependabot::Version.new("#{version.segments[0]}.#{version.segments[1] + 1}.0")
          else
            # For three or more segments, use version.bump
            version.bump # e.g., "~> 2.9.9" becomes upper bound 3.0.0
          end
        else
          version
        end
      end

      # Return the smallest among the effective maximum constraints
      Dependabot::Version.new(effective_max_versions.min) if effective_max_versions.min
    end
  end
end
