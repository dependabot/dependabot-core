# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/npm_and_yarn/requirement"

module Dependabot
  module NpmAndYarn
    module ConstraintHelper
      extend T::Sig

      # Regex Components for Semantic Versioning
      DIGIT = "\\d+"                             # Matches a single number (e.g., "1")
      PRERELEASE = "(?:-[a-zA-Z0-9.-]+)?"        # Matches optional pre-release tag (e.g., "-alpha")
      BUILD_METADATA = "(?:\\+[a-zA-Z0-9.-]+)?"  # Matches optional build metadata (e.g., "+001")

      # Matches semantic versions:
      VERSION = T.let("#{DIGIT}(?:\\.#{DIGIT}){0,2}#{PRERELEASE}#{BUILD_METADATA}".freeze, String)

      VERSION_REGEX = /^#{VERSION}$/

      # Base regex for SemVer (major.minor.patch[-prerelease][+build])
      # This pattern extracts valid semantic versioning strings based on the SemVer 2.0 specification.
      SEMVER_REGEX = /
          (?<version>\d+\.\d+\.\d+)               # Match major.minor.patch (e.g., 1.2.3)
          (?:-(?<prerelease>[a-zA-Z0-9.-]+))?     # Optional prerelease (e.g., -alpha.1, -rc.1, -beta.5)
          (?:\+(?<build>[a-zA-Z0-9.-]+))?         # Optional build metadata (e.g., +build.20231101, +exp.sha.5114f85)
        /x

      # Full SemVer validation regex (ensures the entire string is a valid SemVer)
      # This ensures the entire input strictly follows SemVer, without extra characters before/after.
      SEMVER_VALIDATION_REGEX = /^#{SEMVER_REGEX}$/

      # SemVer constraint regex (supports package.json version constraints)
      # This pattern ensures proper parsing of SemVer versions with optional operators.
      SEMVER_CONSTRAINT_REGEX = /
                (?: (>=|<=|>|<|=|~|\^)\s*)?  # Make operators optional (e.g., >=, ^, ~)
                (\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?)  # Match full SemVer versions
                | (\*|latest) # Match wildcard (*) or 'latest'
              /x

      # /(>=|<=|>|<|=|~|\^)\s*(\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?)|(\*|latest)/

      SEMVER_OPERATOR_REGEX = /^(>=|<=|>|<|~|\^|=)$/

      # Constraint Types as Constants
      CARET_CONSTRAINT_REGEX = /^\^\s*(#{VERSION})$/
      TILDE_CONSTRAINT_REGEX = /^~\s*(#{VERSION})$/
      EXACT_CONSTRAINT_REGEX = /^\s*(#{VERSION})$/
      GREATER_THAN_EQUAL_REGEX = /^>=\s*(#{VERSION})$/
      LESS_THAN_EQUAL_REGEX = /^<=\s*(#{VERSION})$/
      GREATER_THAN_REGEX = /^>\s*(#{VERSION})$/
      LESS_THAN_REGEX = /^<\s*(#{VERSION})$/
      WILDCARD_REGEX = /^\*$/
      LATEST_REGEX = /^latest$/
      SEMVER_CONSTANTS = ["*", "latest"].freeze

      # Unified Regex for Valid Constraints
      VALID_CONSTRAINT_REGEX = T.let(
        Regexp.union(
          CARET_CONSTRAINT_REGEX,
          TILDE_CONSTRAINT_REGEX,
          EXACT_CONSTRAINT_REGEX,
          GREATER_THAN_EQUAL_REGEX,
          LESS_THAN_EQUAL_REGEX,
          GREATER_THAN_REGEX,
          LESS_THAN_REGEX,
          WILDCARD_REGEX,
          LATEST_REGEX
        ).freeze,
        Regexp
      )

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
      def self.extract_ruby_constraints(constraint_expression, dependabot_versions = nil)
        parsed_constraints = parse_constraints(constraint_expression, dependabot_versions)

        return nil unless parsed_constraints

        parsed_constraints.filter_map { |parsed| parsed[:constraint] }
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity
      sig do
        params(constraint_expression: T.nilable(String))
          .returns(T.nilable(T::Array[String]))
      end
      def self.split_constraints(constraint_expression)
        normalized_constraint = constraint_expression&.strip
        return [] if normalized_constraint.nil? || normalized_constraint.empty?

        # Split constraints by logical OR (`||`)
        constraint_groups = normalized_constraint.split("||")

        # Split constraints by logical AND (`,`)
        constraint_groups = constraint_groups.map do |or_constraint|
          or_constraint.split(",").map(&:strip)
        end.flatten

        constraint_groups = constraint_groups.map do |constraint|
          tokens = constraint.split(/\s+/).map(&:strip)

          and_constraints = []

          previous = T.let(nil, T.nilable(String))
          operator = T.let(false, T.nilable(T::Boolean))
          wildcard = T.let(false, T::Boolean)

          tokens.each do |token|
            token = token.strip
            next if token.empty?

            # Invalid constraint if wildcard and anything else
            return nil if wildcard

            # If token is one of the operators (>=, <=, >, <, ~, ^, =)
            if token.match?(SEMVER_OPERATOR_REGEX)
              wildcard = false
              operator = true
            # If token is wildcard or latest
            elsif token.match?(/(\*|latest)/)
              and_constraints << token
              wildcard = true
              operator = false
            # If token is exact version (e.g., "1.2.3")
            elsif token.match(VERSION_REGEX)
              and_constraints << if operator
                                   "#{previous}#{token}"
                                 else
                                   token
                                 end
              wildcard = false
              operator = false
            # If token is a valid constraint (e.g., ">=1.2.3", "<=2.0.0")
            elsif token.match(VALID_CONSTRAINT_REGEX)
              return nil if operator

              and_constraints << token

              wildcard = false
              operator = false
            else
              # invalid constraint
              return nil
            end
            previous = token
          end
          and_constraints.uniq
        end.flatten
        constraint_groups if constraint_groups.any?
      end

      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity

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
        parsed_constraints = parse_constraints(constraint_expression, dependabot_versions)

        return nil if parsed_constraints.nil? || parsed_constraints.empty?

        parsed_versions = parsed_constraints.filter_map { |parsed| parsed[:version] }
        parsed_versions = parsed_versions.map { |version| Version.new(version) }
        candidates = T.let(parsed_versions + (dependabot_versions || []), T::Array[Dependabot::Version])

        return candidates.max&.to_s if unconstrained_expression?(constraint_expression)

        matching_versions = matching_versions_for(constraint_expression, candidates, dependabot_versions)

        preferred_version = supported_major_version(constraint_expression, dependabot_versions, matching_versions)
        return preferred_version if preferred_version

        matching_versions.max&.to_s
      end

      sig do
        params(
          constraint_expression: T.nilable(String),
          candidates: T::Array[Dependabot::Version],
          dependabot_versions: T.nilable(T::Array[Dependabot::Version])
        ).returns(T::Array[Dependabot::Version])
      end
      def self.matching_versions_for(constraint_expression, candidates, dependabot_versions = nil)
        requirements = Requirement.requirements_array(constraint_expression)

        candidates.select do |version|
          # A bare major alias (e.g. "10", with no minor/patch component) stands in
          # for an as-yet-unknown cached release; this is only meaningful when the
          # caller supplied `dependabot_versions` (i.e. we're resolving an engine
          # constraint against the set of majors Dependabot can select from), so we
          # key off the candidate's own string form rather than value-equality
          # against `dependabot_versions`, since a concrete literal version (e.g.
          # "8.0.0") is `==` to its bare-major counterpart ("8") in Gem::Version.
          if dependabot_versions && bare_major_alias?(version)
            # `version` is a bare major alias (e.g. "10"): Corepack will actually
            # install whichever release of that major it has cached (typically the
            # latest patch), and we have no way to know that concrete version here.
            # Only accept the alias when the *entire* major range is contained by
            # the requirement, so that no matter which release Corepack resolves,
            # it is guaranteed to satisfy the constraint. Merely overlapping is not
            # enough: e.g. "<10.1" overlaps major 10's range, but the actual cached
            # release (e.g. 10.9.4) could still violate it.
            requirements.any? { |requirement| major_fully_satisfies_requirement?(version, requirement) }
          else
            requirements.any? { |requirement| requirement.satisfied_by?(version) }
          end
        end
      end

      sig { params(version: Dependabot::Version).returns(T::Boolean) }
      def self.bare_major_alias?(version)
        !!version.to_s.match?(/\A\d+\z/)
      end

      # Checks whether *every* possible release within `major_version`'s major line
      # (i.e. the whole [major.0.0, (major + 1).0.0) range) would satisfy
      # `requirement`, so that selecting the major is safe regardless of which
      # concrete release Corepack ends up resolving and caching for it.
      sig { params(major_version: Dependabot::Version, requirement: Requirement).returns(T::Boolean) }
      def self.major_fully_satisfies_requirement?(major_version, requirement)
        major_low = major_version
        major_high = Version.new("#{major_version.to_s.to_i + 1}.0.0")

        requirement_pairs = T.cast(requirement.requirements, T::Array[[String, Gem::Version]])

        requirement_pairs.all? do |operator, req_version|
          # Converted "^"/"~" requirements express an exclusive upper bound using
          # Gem's prerelease-bump idiom (e.g. "< 11.0.0.a" for "< 11.0.0"), which
          # would otherwise sort below the intended release boundary. Normalize by
          # stripping any such prerelease sentinel before comparing.
          version = Version.new(req_version.release.to_s)

          case operator
          when ">="
            major_low >= version
          when ">"
            major_low > version
          when "<=", "<"
            major_high <= version
          when "~>"
            # A pessimistic ("~>") requirement is satisfied by [version, version.bump).
            # A bare major (e.g. engines.npm: "10") or "~10"/"~>10" normalize to a
            # two-segment "~> 10.0", whose bump lands exactly on the next major, so
            # the whole major range is contained. A more specific "~> 10.2" only
            # bumps the minor, so it can't contain the entire major.
            version <= major_low && major_high <= version.bump
          else
            # "=" (an exact version) and any other operator can never bound an
            # entire major range, so treat the major as unsafe to select.
            false
          end
        end
      end

      sig { params(constraint_expression: T.nilable(String)).returns(T::Boolean) }
      def self.unconstrained_expression?(constraint_expression)
        constraint_expression.to_s.split("||").map(&:strip).any? do |group|
          SEMVER_CONSTANTS.include?(group)
        end
      end

      sig do
        params(
          constraint_expression: T.nilable(String),
          dependabot_versions: T.nilable(T::Array[Dependabot::Version]),
          matching_versions: T::Array[Dependabot::Version]
        ).returns(T.nilable(String))
      end
      def self.supported_major_version(constraint_expression, dependabot_versions, matching_versions)
        return unless constraint_expression.to_s.strip.match?(/\A\^\d+\z/) && dependabot_versions

        dependabot_versions.select { |version| matching_versions.include?(version) }.max&.to_s
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
        splitted_constraints = split_constraints(constraint_expression)

        return unless splitted_constraints

        constraints = to_ruby_constraints_with_versions(splitted_constraints, dependabot_versions)
        constraints
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
          parsed if parsed
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

          # Normalize version: ensure it has major.minor.patch format
          version_parts = T.must(full_version).split(".")
          full_version = case version_parts.length
                         when 1
                           "#{full_version}.0.0" # major only -> major.0.0
                         when 2
                           "#{full_version}.0"   # major.minor -> major.minor.0
                         else
                           full_version          # already major.minor.patch
                         end

          _, major, minor = version_components(full_version)
          return nil if major.nil?

          ruby_constraint =
            if major.to_i.zero?
              minor.nil? ? ">=#{full_version} <1.0.0" : ">=#{full_version} <0.#{minor.to_i + 1}.0"
            else
              ">=#{full_version} <#{major.to_i + 1}.0.0"
            end
          selected_version = if version_parts.length == 1
                               highest_matching_version(
                                 dependabot_versions,
                                 T.must(full_version)
                               ) do |version, lower_bound|
                                 version >= lower_bound && version < Version.new("#{major.to_i + 1}.0.0")
                               end&.to_s
                             end
          { constraint: ruby_constraint, version: selected_version || full_version }
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

          found_version = highest_matching_version(
            dependabot_versions,
            T.must(Regexp.last_match(1))
          ) do |version, constraint_version|
            version >= Version.new(constraint_version)
          end
          { constraint: ">=#{Regexp.last_match(1)}", version: found_version&.to_s }
        when LESS_THAN_EQUAL_REGEX # Less than or equal, e.g., "<=1.2.3"
          return unless Regexp.last_match

          full_version = Regexp.last_match(1)
          { constraint: "<=#{full_version}", version: full_version }
        when GREATER_THAN_REGEX # Greater than, e.g., ">1.2.3"
          return unless Regexp.last_match && Regexp.last_match(1)

          found_version = highest_matching_version(
            dependabot_versions,
            T.must(Regexp.last_match(1))
          ) do |version, constraint_version|
            version > Version.new(constraint_version)
          end
          { constraint: ">#{Regexp.last_match(1)}", version: found_version&.to_s }
        when LESS_THAN_REGEX # Less than, e.g., "<1.2.3"
          return unless Regexp.last_match && Regexp.last_match(1)

          found_version = highest_matching_version(
            dependabot_versions,
            T.must(Regexp.last_match(1))
          ) do |version, constraint_version|
            version < Version.new(constraint_version)
          end
          { constraint: "<#{Regexp.last_match(1)}", version: found_version&.to_s }
        when WILDCARD_REGEX # No specific constraint, resolves to the highest available version
          { constraint: nil, version: dependabot_versions&.max&.to_s }
        when LATEST_REGEX
          { constraint: nil, version: dependabot_versions&.max&.to_s } # Resolves to the latest available version
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
      def self.highest_matching_version(dependabot_versions, constraint_version, &condition)
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

        match = full_version.match(SEMVER_VALIDATION_REGEX)
        return [] unless match

        version = match[:version]
        return [] unless version

        major, minor, patch = version.split(".")
        [version, major, minor, patch, match[:prerelease], match[:build]].compact
      end
    end
  end
end
