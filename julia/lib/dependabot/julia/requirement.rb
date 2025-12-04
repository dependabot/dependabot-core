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
        # Note: Missing compat entry (nil/empty) means any version is acceptable
        return [new(">= 0")] if requirement_string.nil? || requirement_string.empty?

        constraints = requirement_string.split(",").map(&:strip)

        if compound_constraint?(constraints)
          parse_compound_constraint(constraints)
        else
          parse_separate_constraints(constraints)
        end
      rescue Gem::Requirement::BadRequirementError
        [new(">= 0")]
      end

      sig { params(constraints: T::Array[String]).returns(T::Boolean) }
      def self.compound_constraint?(constraints)
        # Compound constraints (e.g., ">= 1.0, < 2.0") have operators and multiple parts
        constraints.length > 1 && constraints.any? { |c| c.match?(/^[<>=~^]/) }
      end

      sig { params(constraints: T::Array[String]).returns(T::Array[Dependabot::Julia::Requirement]) }
      def self.parse_compound_constraint(constraints)
        # Handle compound constraints (e.g., ">= 1.0, < 2.0") as a single requirement
        normalized_constraints = constraints.flat_map { |c| normalize_julia_constraint(c) }
        [new(normalized_constraints)]
      end

      sig { params(constraints: T::Array[String]).returns(T::Array[Dependabot::Julia::Requirement]) }
      def self.parse_separate_constraints(constraints)
        # Handle separate version specs (e.g., "0.34, 0.35") as multiple requirements
        constraints.map { |constraint| new(normalize_julia_constraint(constraint)) }
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

      sig { params(constraint: String).returns(T::Array[String]) }
      def self.normalize_julia_constraint(constraint)
        return normalize_caret_constraint(constraint) if constraint.match?(/^\^(\d+(?:\.\d+)*)/)
        return normalize_tilde_constraint(constraint) if constraint.match?(/^~(\d+(?:\.\d+)*)/)
        return normalize_range_constraint(constraint) if constraint.match?(/^(\d+(?:\.\d+)*)-(\d+(?:\.\d+)*)$/)

        # Julia treats plain version numbers as caret constraints (implicit ^)
        # e.g., "1.2.3" is equivalent to "^1.2.3" which means ">= 1.2.3, < 2.0.0"
        # See: https://pkgdocs.julialang.org/v1/compatibility/
        return normalize_caret_constraint("^#{constraint}") if constraint.match?(/^(\d+(?:\.\d+)*)$/)

        # Return as-is for standard gem requirements (>=, <=, ==, etc.)
        [constraint]
      end

      sig { params(constraint: String).returns(T::Array[String]) }
      private_class_method def self.normalize_caret_constraint(constraint)
        version = T.must(constraint[1..-1])
        parts = version.split(".")
        major = T.must(parts[0]).to_i
        minor = parts[1].to_i
        patch = parts[2].to_i

        # Julia caret semantics:
        # - For 0.0.x: compatible within patch (e.g., 0.0.5 -> 0.0.x, < 0.0.6 or < 0.1.0?)
        # - For 0.x.y: compatible within minor (e.g., 0.34.6 -> 0.34.x, < 0.35.0)
        # - For x.y.z (x > 0): compatible within major (e.g., 1.2.3 -> 1.x.x, < 2.0.0)
        if major.zero? && minor.zero?
          # 0.0.x versions: bump patch
          [">= #{version}", "< 0.0.#{patch + 1}"]
        elsif major.zero?
          # 0.x.y versions: bump minor (0.34.6 -> < 0.35.0)
          [">= #{version}", "< 0.#{minor + 1}.0"]
        else
          # x.y.z versions where x > 0: bump major
          [">= #{version}", "< #{major + 1}.0.0"]
        end
      end

      sig { params(constraint: String).returns(T::Array[String]) }
      private_class_method def self.normalize_tilde_constraint(constraint)
        version = T.must(constraint[1..-1])
        parts = version.split(".")
        major = T.must(parts[0]).to_i
        minor = parts[1].to_i

        # Julia tilde semantics (similar to npm):
        # - For 0.0.x: compatible within patch (same as caret)
        # - For 0.x.y or x.y.z: compatible within minor (bump minor)
        if major.zero? && minor.zero?
          # 0.0.x versions: bump patch
          patch = parts[2].to_i
          [">= #{version}", "< 0.0.#{patch + 1}"]
        elsif major.zero?
          # 0.x.y versions: bump minor (same as caret for 0.x)
          [">= #{version}", "< 0.#{minor + 1}.0"]
        else
          # x.y.z versions where x > 0: bump minor only
          [">= #{version}", "< #{major}.#{minor + 1}.0"]
        end
      end

      sig { params(constraint: String).returns(T::Array[String]) }
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

        [">= #{start_version}", "< #{next_minor}"]
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("julia", Dependabot::Julia::Requirement)
