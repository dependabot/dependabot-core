# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    module ConstraintHelper
      extend T::Sig

      INVALID = "invalid" # Invalid constraint
      # Regex Components for Semantic Versioning
      DIGIT = "\\d+"                             # Matches a single number (e.g., "1")
      PRERELEASE = "(?:-[a-zA-Z0-9.-]+)?"        # Matches optional pre-release tag (e.g., "-alpha")
      BUILD_METADATA = "(?:\\+[a-zA-Z0-9.-]+)?"  # Matches optional build metadata (e.g., "+001")
      DOT = "\\."                                # Matches a literal dot "."

      # Matches semantic versions:
      VERSION = T.let("#{DIGIT}(?:\\.#{DIGIT}){0,2}#{PRERELEASE}#{BUILD_METADATA}".freeze, String)

      # SemVer regex: major.minor.patch[-prerelease][+build]
      SEMVER_REGEX = /^(?<version>\d+\.\d+\.\d+)(?:-(?<prerelease>[a-zA-Z0-9.-]+))?(?:\+(?<build>[a-zA-Z0-9.-]+))?$/

      # Constraint Types as Constants
      CARET_CONSTRAINT_REGEX = T.let(/^\^(#{VERSION})$/, Regexp)
      TILDE_CONSTRAINT_REGEX = T.let(/^~(#{VERSION})$/, Regexp)
      EXACT_CONSTRAINT_REGEX = T.let(/^(#{VERSION})$/, Regexp)
      GREATER_THAN_EQUAL_REGEX = T.let(/^>=(#{VERSION})$/, Regexp)
      LESS_THAN_EQUAL_REGEX = T.let(/^<=(#{VERSION})$/, Regexp)
      GREATER_THAN_REGEX = T.let(/^>(#{VERSION})$/, Regexp)
      LESS_THAN_REGEX = T.let(/^<(#{VERSION})$/, Regexp)
      WILDCARD_REGEX = T.let(/^\*$/, Regexp)

      # Unified Regex for Valid Constraints
      VALID_CONSTRAINT_REGEX = T.let(Regexp.union(
        CARET_CONSTRAINT_REGEX,
        TILDE_CONSTRAINT_REGEX,
        EXACT_CONSTRAINT_REGEX,
        GREATER_THAN_EQUAL_REGEX,
        LESS_THAN_EQUAL_REGEX,
        GREATER_THAN_REGEX,
        LESS_THAN_REGEX,
        WILDCARD_REGEX
      ).freeze, Regexp)

      # Validates if the provided semver constraint expression from a `package.json` is valid.
      # A valid semver constraint expression in `package.json` can consist of multiple groups
      # separated by logical OR (`||`). Within each group, space-separated constraints are treated
      # as logical AND. Each individual constraint must conform to the semver rules defined in
      # `VALID_CONSTRAINT_REGEX`.
      #
      # Example (valid `package.json` semver constraints):
      #   ">=1.2.3 <2.0.0 || ~3.4.5" → Valid (space-separated constraints are AND, `||` is OR)
      #   "^1.0.0 || >=2.0.0 <3.0.0" → Valid (caret and range constraints combined)
      #   "1.2.3" → Valid (exact version)
      #   "*" → Valid (wildcard allows any version)
      #
      # Example (invalid `package.json` semver constraints):
      #   ">=1.2.3 && <2.0.0" → Invalid (`&&` is not valid in semver)
      #   ">=x.y.z" → Invalid (non-numeric version parts are not valid)
      #   "1.2.3 ||" → Invalid (trailing OR operator)
      #
      # @param constraint_expression [String] The semver constraint expression from `package.json` to validate.
      # @return [T::Boolean] Returns true if the constraint expression is valid semver, false otherwise.
      sig { params(constraint_expression: T.nilable(String)).returns(T::Boolean) }
      def self.valid_constraint_expression?(constraint_expression)
        normalized_constraint = constraint_expression&.strip

        # Treat nil or empty input as valid (no constraints)
        return true if normalized_constraint.nil? || normalized_constraint.empty?

        # Split the expression by logical OR (`||`) into groups
        normalized_constraint.split("||").reject(&:empty?).all? do |or_group|
          or_group.split(/\s+/).reject(&:empty?).all? do |and_constraint|
            and_constraint.match?(VALID_CONSTRAINT_REGEX)
          end
        end
      end

      # Extract unique constraints from the given constraint expression.
      # @param constraint_expression [T.nilable(String)] The semver constraint expression.
      # @return [T::Array[String]] The list of unique Ruby-compatible constraints.
      sig do
        params(
          constraint_expression: T.nilable(String),
          dependabot_versions: T.nilable(T::Array[Dependabot::Version])
        )
          .returns(T.nilable(T::Array[String]))
      end
      def self.extract_constraints(constraint_expression, dependabot_versions = nil)
        normalized_constraint = constraint_expression&.strip
        return [] if normalized_constraint.nil? || normalized_constraint.empty?

        parsed_constraints = parse_constraints(normalized_constraint, dependabot_versions)

        return nil unless parsed_constraints

        parsed_constraints.filter_map { |parsed| parsed[:constraint] }
      end

      # Find the highest version from the given constraint expression.
      # @param constraint_expression [T.nilable(String)] The semver constraint expression.
      # @return [T.nilable(String)] The highest version, or nil if no versions are available.
      sig do
        params(
          constraint_expression: T.nilable(String),
          dependabot_versions: T.nilable(T::Array[Dependabot::Version])
        )
          .returns(T.nilable(String))
      end
      def self.find_highest_version_from_constraint_expression(constraint_expression, dependabot_versions = nil)
        normalized_constraint = constraint_expression&.strip
        return nil if normalized_constraint.nil? || normalized_constraint.empty?

        parsed_constraints = parse_constraints(normalized_constraint, dependabot_versions)

        return nil unless parsed_constraints

        parsed_constraints
          .filter_map { |parsed| parsed[:version] } # Extract all versions
          .max_by { |version| Version.new(version) } # Find the highest version
      end

      # Parse all constraints (split by logical OR `||`) and convert to Ruby-compatible constraints.
      # Return:
      #   - `nil` if the constraint expression is invalid
      #   - `[]` if the constraint expression is valid but represents "no constraints"
      #   - An array of hashes for valid constraints with details about the constraint and version
      sig do
        params(
          constraint_expression: T.nilable(String),
          dependabot_versions: T.nilable(T::Array[Dependabot::Version])
        )
          .returns(T.nilable(T::Array[T::Hash[Symbol, T.nilable(String)]]))
      end
      def self.parse_constraints(constraint_expression, dependabot_versions = nil)
        normalized_constraint = constraint_expression&.strip

        # Return an empty array for valid "no constraints" (nil or empty input)
        return [] if normalized_constraint.nil? || normalized_constraint.empty?

        # Return nil for invalid constraints
        return nil unless valid_constraint_expression?(normalized_constraint)

        # Parse valid constraints
        normalized_constraint.split("||").flat_map do |or_group|
          or_group.strip.split(/\s+/).map(&:strip)
        end.then do |normalized_constraints| # rubocop:disable Style/MultilineBlockChain
          to_ruby_constraints_with_versions(normalized_constraints, dependabot_versions)
        end.uniq { |parsed| parsed[:constraint] } # Ensure uniqueness based on `:constraint` # rubocop:disable Style/MultilineBlockChain
      end

      sig do
        params(
          constraints: T::Array[String],
          dependabot_versions: T.nilable(T::Array[Dependabot::Version])
        ).returns(T::Array[T::Hash[Symbol, T.nilable(String)]])
      end
      def self.to_ruby_constraints_with_versions(constraints, dependabot_versions = [])
        constraints.filter_map do |constraint|
          parsed = to_ruby_constraint_with_version(constraint, dependabot_versions)
          parsed if parsed && parsed[:constraint] # Only include valid constraints
        end.uniq
      end

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # Converts a semver constraint to a Ruby-compatible constraint and extracts the version, if available.
      # @param constraint [String] The semver constraint to parse.
      # @return [T.nilable(T::Hash[Symbol, T.nilable(String)])] Returns the Ruby-compatible constraint and the version,
      # if available, or nil if the constraint is invalid.
      #
      # @example
      #  to_ruby_constraint_with_version("=1.2.3") # => { constraint: "=1.2.3", version: "1.2.3" }
      #  to_ruby_constraint_with_version("^1.2.3") # => { constraint: ">=1.2.3 <2.0.0", version: "1.2.3" }
      #  to_ruby_constraint_with_version("*")      # => { constraint: nil, version: nil }
      #  to_ruby_constraint_with_version("invalid") # => nil
      sig do
        params(
          constraint: String,
          dependabot_versions: T.nilable(T::Array[Dependabot::Version])
        )
          .returns(T.nilable(T::Hash[Symbol, T.nilable(String)]))
      end
      def self.to_ruby_constraint_with_version(constraint, dependabot_versions = [])
        return nil if constraint.empty?

        case constraint
        when EXACT_CONSTRAINT_REGEX # Exact version, e.g., "1.2.3-alpha"
          return unless Regexp.last_match

          full_version = Regexp.last_match(1)
          { constraint: "=#{full_version}", version: full_version }
        when CARET_CONSTRAINT_REGEX # Caret constraint, e.g., "^1.2.3"
          return unless Regexp.last_match

          full_version = Regexp.last_match(1)
          _, major, minor = version_components(full_version)
          return nil if major.nil?

          ruby_constraint =
            if major.to_i.zero?
              minor.nil? ? ">=#{full_version} <1.0.0" : ">=#{full_version} <0.#{minor.to_i + 1}.0"
            else
              ">=#{full_version} <#{major.to_i + 1}.0.0"
            end
          { constraint: ruby_constraint, version: full_version }
        when TILDE_CONSTRAINT_REGEX # Tilde constraint, e.g., "~1.2.3"
          return unless Regexp.last_match

          full_version = Regexp.last_match(1)
          _, major, minor = version_components(full_version)
          ruby_constraint =
            if minor.nil?
              ">=#{full_version} <#{major.to_i + 1}.0.0"
            else
              ">=#{full_version} <#{major}.#{minor.to_i + 1}.0"
            end
          { constraint: ruby_constraint, version: full_version }
        when GREATER_THAN_EQUAL_REGEX # Greater than or equal, e.g., ">=1.2.3"
          return unless Regexp.last_match && Regexp.last_match(1)

          found_version = satisfying_version(dependabot_versions, T.must(Regexp.last_match(1))) do |version, constraint|
            version >= Version.new(constraint)
          end
          { constraint: ">=#{Regexp.last_match(1)}", version: found_version }
        when LESS_THAN_EQUAL_REGEX # Less than or equal, e.g., "<=1.2.3"
          return unless Regexp.last_match

          full_version = Regexp.last_match(1)
          { constraint: "<=#{full_version}", version: full_version }
        when GREATER_THAN_REGEX # Greater than, e.g., ">1.2.3"
          return unless Regexp.last_match

          found_version = satisfying_version(dependabot_versions, T.must(Regexp.last_match(1))) do |version, constraint|
            version > Version.new(constraint)
          end

          { constraint: ">#{Regexp.last_match(1)}", version: found_version }
        when LESS_THAN_REGEX # Less than, e.g., "<1.2.3"
          return unless Regexp.last_match

          found_version = satisfying_version(dependabot_versions, T.must(Regexp.last_match(1))) do |version, constraint|
            version < Version.new(constraint)
          end

          { constraint: "<#{Regexp.last_match(1)}", version: found_version }
        when WILDCARD_REGEX # Wildcard
          { constraint: nil, version: dependabot_versions&.max } # Explicitly valid but no specific constraint
        end
      end

      sig do
        params(
          dependabot_versions: T.nilable(T::Array[Dependabot::Version]),
          constraint_version: String,
          condition: T.proc.params(version: Dependabot::Version, constraint: Dependabot::Version).returns(T::Boolean)
        )
          .returns(T.nilable(Dependabot::Version))
      end
      def self.satisfying_version(dependabot_versions, constraint_version, &condition)
        return unless dependabot_versions&.any?

        # Returns the highest version that satisfies the condition, or nil if none.
        dependabot_versions
          .sort
          .reverse
          .find { |version| condition.call(version, Version.new(constraint_version)) } # rubocop:disable Performance/RedundantBlockCall
      end

      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity

      # Parses a semantic version string into its components as per the SemVer spec
      # Example: "1.2.3-alpha+001" → ["1.2.3", "1", "2", "3", "alpha", "001"]
      sig { params(full_version: T.nilable(String)).returns(T.nilable(T::Array[String])) }
      def self.version_components(full_version)
        return [] if full_version.nil?

        match = full_version.match(SEMVER_REGEX)
        return [] unless match

        version = match[:version]
        return [] unless version

        major, minor, patch = version.split(".")
        [version, major, minor, patch, match[:prerelease], match[:build]].compact
      end
    end
  end
end
