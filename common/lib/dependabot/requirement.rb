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
    sig { returns(T.nilable(Dependabot::Version)) }
    def min_version
      # Select constraints with minimum operators
      min_constraints = requirements.select { |op, _| MINIMUM_OPERATORS.include?(op) }

      # Process each minimum constraint using the respective handler
      effective_min_versions = min_constraints.filter_map do |op, version|
        handle_min_operator(op, version.is_a?(Dependabot::Version) ? version : Dependabot::Version.new(version))
      end

      # Return the maximum among the effective minimum constraints
      Dependabot::Version.new(effective_min_versions.max) if effective_min_versions.any?
    end

    # Returns the lowest upper limit among all maximum constraints.
    sig { returns(T.nilable(Dependabot::Version)) }
    def max_version
      # Select constraints with maximum operators
      max_constraints = requirements.select { |op, _| MAXIMUM_OPERATORS.include?(op) }

      # Process each maximum constraint using the respective handler
      effective_max_versions = max_constraints.filter_map do |op, version|
        handle_max_operator(op, version.is_a?(Dependabot::Version) ? version : Dependabot::Version.new(version))
      end

      # Return the minimum among the effective maximum constraints
      Dependabot::Version.new(effective_max_versions.min) if effective_max_versions.any?
    end

    # Dynamically handles minimum operators
    sig { params(operator: String, version: Dependabot::Version).returns(T.nilable(Dependabot::Version)) }
    def handle_min_operator(operator, version)
      case operator
      when ">=" then handle_gte_min(version)
      when ">"  then handle_gt_min(version)
      when "~>" then handle_tilde_pessimistic_min(version)
      end
    end

    # Dynamically handles maximum operators
    sig { params(operator: String, version: Dependabot::Version).returns(T.nilable(Dependabot::Version)) }
    def handle_max_operator(operator, version)
      case operator
      when "<=" then handle_lte_max(version)
      when "<"  then handle_lt_max(version)
      when "~>" then handle_tilde_pessimistic_max(version)
      end
    end

    # Methods for handling minimum constraints
    sig { params(version: Dependabot::Version).returns(Dependabot::Version) }
    def handle_gte_min(version)
      version
    end

    sig { params(version: Dependabot::Version).returns(Dependabot::Version) }
    def handle_gt_min(version)
      version
    end

    sig { params(version: Dependabot::Version).returns(Dependabot::Version) }
    def handle_tilde_pessimistic_min(version)
      version
    end

    # Methods for handling maximum constraints
    sig { params(version: Dependabot::Version).returns(Dependabot::Version) }
    def handle_lte_max(version)
      version
    end

    sig { params(version: Dependabot::Version).returns(Dependabot::Version) }
    def handle_lt_max(version)
      version
    end

    sig { params(version: Dependabot::Version).returns(Dependabot::Version) }
    def handle_tilde_pessimistic_max(version)
      case version.segments.length
      when 1
        bump_major_segment(version)
      when 2
        bump_minor_segment(version)
      else
        bump_version(version)
      end
    end

    private

    sig { params(version: Dependabot::Version).returns(Dependabot::Version) }
    def bump_major_segment(version)
      Dependabot::Version.new("#{version.segments[0].to_i + 1}.0.0")
    end

    sig { params(version: Dependabot::Version).returns(Dependabot::Version) }
    def bump_minor_segment(version)
      Dependabot::Version.new("#{version.segments[0]}.#{version.segments[1].to_i + 1}.0")
    end

    sig { params(version: Dependabot::Version).returns(Dependabot::Version) }
    def bump_version(version)
      Dependabot::Version.new(version.bump)
    end
  end
end
