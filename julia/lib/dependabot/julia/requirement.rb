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
        # Compound constraints (e.g., ">= 1.0, < 2.0") are when explicit comparison operators
        # (>=, <=, <, >, =) work together to define a single range.
        # Separate constraints (e.g., "^1.10, 2" or "0.34, 0.35") use version specs
        # (with or without ^/~) as OR conditions - any matching spec is acceptable.
        # Only treat as compound if ALL constraints use explicit comparison operators.
        return false if constraints.length <= 1

        constraints.all? { |c| c.match?(/^[<>=]/) }
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

      sig { params(version_string: String).returns([String, Integer, Integer, Integer, Integer]) }
      private_class_method def self.parse_version_parts(version_string)
        parts = version_string.split(".")
        [
          version_string,
          parts.length,
          T.must(parts[0]).to_i,
          parts[1].to_i,
          parts[2].to_i
        ]
      end

      sig { params(major: Integer, minor: Integer, patch: Integer, num_parts: Integer).returns(String) }
      private_class_method def self.caret_upper_bound(major, minor, patch, num_parts)
        # Julia caret semantics: upper bound determined by left-most non-zero digit
        return "#{major + 1}.0.0" if major.positive?
        return "0.#{minor + 1}.0" if minor.positive?
        return "0.0.#{patch + 1}" if num_parts == 3
        return "0.1.0" if num_parts == 2

        "1.0.0"
      end

      sig { params(constraint: String).returns(T::Array[String]) }
      private_class_method def self.normalize_caret_constraint(constraint)
        version, num_parts, major, minor, patch = parse_version_parts(T.must(constraint[1..-1]))

        # Julia caret semantics (from https://pkgdocs.julialang.org/v1/compatibility/):
        # ^1.2.3 -> [1.2.3, 2.0.0), ^0.2.3 -> [0.2.3, 0.3.0), ^0.0.3 -> [0.0.3, 0.0.4)
        # ^0.0 -> [0.0.0, 0.1.0), ^0 -> [0.0.0, 1.0.0)
        [">= #{version}", "< #{caret_upper_bound(major, minor, patch, num_parts)}"]
      end

      sig { params(major: Integer, minor: Integer, patch: Integer, num_parts: Integer).returns(String) }
      private_class_method def self.tilde_upper_bound(major, minor, patch, num_parts)
        # Julia tilde semantics: ~1 equivalent to ^1, otherwise bump minor (except 0.0.x bumps patch)
        return "#{major + 1}.0.0" if num_parts == 1
        return "0.0.#{patch + 1}" if major.zero? && minor.zero? && num_parts == 3
        return "0.1.0" if major.zero? && minor.zero?

        "#{major}.#{minor + 1}.0"
      end

      sig { params(constraint: String).returns(T::Array[String]) }
      private_class_method def self.normalize_tilde_constraint(constraint)
        version, num_parts, major, minor, patch = parse_version_parts(T.must(constraint[1..-1]))

        # Julia tilde semantics (from https://pkgdocs.julialang.org/v1/compatibility/):
        # ~1.2.3 -> [1.2.3, 1.3.0), ~1 -> [1.0.0, 2.0.0), ~0.0.3 -> [0.0.3, 0.0.4)
        [">= #{version}", "< #{tilde_upper_bound(major, minor, patch, num_parts)}"]
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
