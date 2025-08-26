# typed: strong
# frozen_string_literal: true

require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Julia
    class Requirement < Dependabot::Requirement
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Dependabot::Julia::Requirement]) }
      def self.requirements_array(requirement_string)
        # Julia version specifiers can be:
        # - Exact: "1.2.3"
        # - Range: "1.2-1.3", ">=1.0, <2.0"
        # - Caret: "^1.2" (compatible within major version)
        # - Tilde: "~1.2.3" (compatible within minor version)
        # - Wildcard: "*" (any version)
        return [new(">= 0")] if requirement_string.nil? || requirement_string.empty? || requirement_string == "*"

        # Split by comma for multiple constraints
        constraints = requirement_string.split(",").map(&:strip)

        constraints.map do |constraint|
          # Handle Julia-specific patterns
          normalized_constraint = normalize_julia_constraint(constraint)
          new(normalized_constraint)
        end
      rescue Gem::Requirement::BadRequirementError
        [new(">= 0")]
      end

      sig { params(requirement_string: String).returns(T::Array[Dependabot::Julia::Requirement]) }
      def self.parse_requirements(requirement_string)
        requirements_array(requirement_string)
      end

      sig { params(version: String).returns(String) }
      def self.normalize_version(version)
        # Remove 'v' prefix if present (common in Julia)
        version = version.sub(/^v/, "") if version.match?(/^v\d/)
        version
      end

      sig { params(constraint: String).returns(String) }
      def self.normalize_julia_constraint(constraint)
        return normalize_caret_constraint(constraint) if constraint.match?(/^\^(\d+(?:\.\d+)*)/)
        return normalize_tilde_constraint(constraint) if constraint.match?(/^~(\d+(?:\.\d+)*)/)
        return normalize_range_constraint(constraint) if constraint.match?(/^(\d+(?:\.\d+)*)-(\d+(?:\.\d+)*)$/)

        # Return as-is for standard gem requirements (>=, <=, ==, etc.)
        constraint
      end

      sig { params(constraint: String).returns(String) }
      private_class_method def self.normalize_caret_constraint(constraint)
        version = T.must(constraint[1..-1])
        parts = version.split(".")
        major = T.must(parts[0])
        return ">= #{version}.0.0, < #{major.to_i + 1}.0.0" if parts.length == 1

        ">= #{version}, < #{major.to_i + 1}.0.0"
      end

      sig { params(constraint: String).returns(String) }
      private_class_method def self.normalize_tilde_constraint(constraint)
        version = T.must(constraint[1..-1])
        parts = version.split(".")
        return ">= #{version}, < #{T.must(parts[0]).to_i + 1}.0.0" unless parts.length >= 2

        major = T.must(parts[0])
        minor = T.must(parts[1])
        ">= #{version}, < #{major}.#{minor.to_i + 1}.0"
      end

      sig { params(constraint: String).returns(String) }
      private_class_method def self.normalize_range_constraint(constraint)
        start_version, end_version = constraint.split("-")
        end_parts = T.must(end_version).split(".")

        next_minor = if end_parts.length >= 2
                       major = T.must(end_parts[0])
                       minor = T.must(end_parts[1])
                       "#{major}.#{minor.to_i + 1}.0"
                     else
                       "#{T.must(end_parts[0]).to_i + 1}.0.0"
                     end

        ">= #{start_version}, < #{next_minor}"
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("julia", Dependabot::Julia::Requirement)
