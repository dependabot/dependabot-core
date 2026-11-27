# typed: strict
# frozen_string_literal: true

################################################################################
# For more details on rust version constraints, see:                           #
# - https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html     #
# - https://steveklabnik.github.io/semver/semver/index.html                    #
################################################################################

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/cargo/version"

module Dependabot
  module Cargo
    class Requirement < Dependabot::Requirement
      extend T::Sig

      quoted = OPS.keys.map { |k| Regexp.quote(k) }.join("|")
      version_pattern = Cargo::Version::VERSION_PATTERN

      PATTERN_RAW = T.let("\\s*(#{quoted})?\\s*(#{version_pattern})\\s*".freeze, String)
      PATTERN = /\A#{PATTERN_RAW}\z/
      COMPARATOR_PATTERN = /
        \A\s*
        (?<operator>==|>=|<=|=|>|<|~|\^)?
        \s*
        (?<major>\d+)
        (?:\.(?<minor>\d+|\*))?
        (?:\.(?<patch>\d+|\*))?
        (?<prerelease>-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?
        (?<build>\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?
        \s*\z
      /x

      class Comparator < T::Struct
        const :operator, Symbol
        const :major, Integer
        const :minor, T.nilable(Integer)
        const :patch, T.nilable(Integer)
        const :version, Cargo::Version
      end

      # Use Cargo::Version rather than Gem::Version to ensure that
      # pre-release versions aren't transformed.
      sig { override.params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        return ["=", Cargo::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Cargo::Version.new(T.must(matches[2]))]
      end

      # For consistency with other languages, we define a requirements array.
      # Rust doesn't have an `OR` separator for requirements, so it always
      # contains a single element.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      # Parses a pre-commit Rust additional_dependency string.
      # Formats: "package_name:version", "cli:package_name:version"
      sig { params(dep_string: String).returns(T.nilable(T::Hash[Symbol, T.nilable(String)])) }
      def self.parse_dep_string(dep_string)
        stripped = dep_string.strip
        return nil if stripped.empty?

        parts = stripped.split(":", -1)

        cli = false
        if parts.first&.downcase == "cli"
          return nil if parts.length < 3

          cli = true
          parts.shift
        end

        return nil if parts.length < 2

        name = T.must(parts[0])
        constraint = T.must(parts[1..]).join(":")
        return nil if name.empty? || constraint.strip.empty?

        constraint = constraint.strip
        version = extract_version(constraint)

        {
          name: name,
          normalised_name: name,
          version: version,
          requirement: constraint,
          extras: cli ? "cli" : nil
        }
      end

      sig { params(constraint: String).returns(T.nilable(String)) }
      def self.extract_version(constraint)
        version_part = constraint.sub(/\A(?:[~^]|[><=]+)\s*/, "")

        return nil unless Cargo::Version.correct?(version_part)

        version_part
      end

      private_class_method :extract_version

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        raw_requirements = requirements.flatten
        @raw_comparators = T.let(
          raw_requirements.flat_map { |requirement| T.must(requirement).split(",") }.map(&:strip),
          T::Array[String]
        )
        @comparators = T.let(nil, T.nilable(T::Array[Comparator]))

        normalized_requirements = @raw_comparators.map do |comparator|
          convert_rust_constraint_to_ruby_constraint(comparator)
        end

        super(normalized_requirements)
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        prerelease_opted_in?(version) && bounds_satisfied_by?(version)
      end

      sig { params(version: Gem::Version).returns(T::Boolean) }
      def bounds_satisfied_by?(version)
        version = Cargo::Version.new(version.to_s)

        comparators.all? { |comparator| comparator_satisfied_by?(comparator, version) }
      end

      sig { params(version: Gem::Version).returns(T::Boolean) }
      def prerelease_opted_in?(version)
        version = Cargo::Version.new(version.to_s)
        return true unless version.prerelease?

        major, minor, patch = version_parts(version)
        comparators.any? do |comparator|
          comparator.major == major &&
            comparator.minor == minor &&
            comparator.patch == patch &&
            comparator.version.prerelease?
        end
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by_range?(version)
        requirements_satisfied_by?(gem_version(version))
      end

      private

      sig { returns(T::Array[Comparator]) }
      def comparators
        return @comparators if @comparators

        @comparators = @raw_comparators.filter_map { |comparator| parse_comparator(comparator) }
      end

      sig { params(version: Gem::Version).returns(T::Boolean) }
      def requirements_satisfied_by?(version)
        requirements.all? do |operator, requirement|
          policy_requirement = gem_version(requirement)
          (OPS[operator] || OPS["="]).call(version, policy_requirement)
        end
      end

      sig { params(version: Gem::Version).returns(Gem::Version) }
      def gem_version(version)
        Gem::Version.new(version.to_s.split("+", 2).first)
      end

      sig { params(comparator: Comparator, version: Gem::Version).returns(T::Boolean) }
      def comparator_satisfied_by?(comparator, version)
        operator = comparator.operator
        case operator
        when :exact, :wildcard then exact_match?(comparator, version)
        when :greater then greater_match?(comparator, version)
        when :greater_eq then exact_match?(comparator, version) || greater_match?(comparator, version)
        when :less then less_match?(comparator, version)
        when :less_eq then exact_match?(comparator, version) || less_match?(comparator, version)
        when :tilde then tilde_match?(comparator, version)
        when :caret then caret_match?(comparator, version)
        else raise "Unknown Cargo comparator operator: #{operator}"
        end
      end

      sig { params(comparator: Comparator, version: Gem::Version).returns(T::Boolean) }
      def exact_match?(comparator, version)
        major, minor, patch = version_parts(version)
        return false unless major == comparator.major
        return true unless comparator.minor
        return false unless minor == comparator.minor
        return true unless comparator.patch
        return false unless patch == comparator.patch

        prerelease(version) == prerelease(comparator.version)
      end

      sig { params(comparator: Comparator, version: Gem::Version).returns(T::Boolean) }
      def greater_match?(comparator, version)
        major, minor, patch = version_parts(version)
        return major > comparator.major if major != comparator.major
        return false unless comparator.minor
        return minor > T.must(comparator.minor) if minor != comparator.minor
        return false unless comparator.patch
        return patch > T.must(comparator.patch) if patch != comparator.patch

        prerelease_comparison(version, comparator.version).positive?
      end

      sig { params(comparator: Comparator, version: Gem::Version).returns(T::Boolean) }
      def less_match?(comparator, version)
        major, minor, patch = version_parts(version)
        return major < comparator.major if major != comparator.major
        return false unless comparator.minor
        return minor < T.must(comparator.minor) if minor != comparator.minor
        return false unless comparator.patch
        return patch < T.must(comparator.patch) if patch != comparator.patch

        prerelease_comparison(version, comparator.version).negative?
      end

      sig { params(comparator: Comparator, version: Gem::Version).returns(T::Boolean) }
      def tilde_match?(comparator, version)
        major, minor, patch = version_parts(version)
        return false unless major == comparator.major
        return false if comparator.minor && minor != comparator.minor
        return patch > T.must(comparator.patch) if comparator.patch && patch != comparator.patch

        prerelease_comparison(version, comparator.version) >= 0
      end

      sig { params(comparator: Comparator, version: Gem::Version).returns(T::Boolean) }
      def caret_match?(comparator, version)
        major, minor, patch = version_parts(version)
        return false unless major == comparator.major
        return true unless comparator.minor
        return partial_caret_match?(comparator, minor) unless comparator.patch

        release_match = full_caret_release_match(comparator, minor, patch)
        return release_match unless release_match.nil?

        prerelease_comparison(version, comparator.version) >= 0
      end

      sig { params(comparator: Comparator, minor: Integer).returns(T::Boolean) }
      def partial_caret_match?(comparator, minor)
        return minor >= T.must(comparator.minor) if comparator.major.positive?

        minor == comparator.minor
      end

      sig do
        params(
          comparator: Comparator,
          minor: Integer,
          patch: Integer
        ).returns(T.nilable(T::Boolean))
      end
      def full_caret_release_match(comparator, minor, patch)
        if comparator.major.positive?
          return minor > T.must(comparator.minor) if minor != comparator.minor

          patch > T.must(comparator.patch) if patch != comparator.patch
        elsif T.must(comparator.minor).positive?
          return false if minor != comparator.minor

          patch > T.must(comparator.patch) if patch != comparator.patch
        elsif minor != comparator.minor || patch != comparator.patch
          false
        end
      end

      sig { params(version: Gem::Version).returns([Integer, Integer, Integer]) }
      def version_parts(version)
        segments = version.release.segments.map(&:to_i)
        [segments.fetch(0, 0), segments.fetch(1, 0), segments.fetch(2, 0)]
      end

      sig { params(version: Gem::Version).returns(String) }
      def prerelease(version)
        version.to_s.split("+", 2).first.to_s[/-(.+)\z/, 1].to_s
      end

      sig { params(version: Gem::Version, requirement: Gem::Version).returns(Integer) }
      def prerelease_comparison(version, requirement)
        version_prerelease = prerelease(version)
        requirement_prerelease = prerelease(requirement)
        return 0 if version_prerelease == requirement_prerelease
        return 1 if version_prerelease.empty?
        return -1 if requirement_prerelease.empty?

        version_for_comparison = Cargo::Version.new("0.0.0-#{version_prerelease}")
        requirement_for_comparison = Cargo::Version.new("0.0.0-#{requirement_prerelease}")
        T.must(version_for_comparison <=> requirement_for_comparison)
      end

      sig { params(req_string: String).returns(T.nilable(Comparator)) }
      def parse_comparator(req_string)
        normalized = normalize_wildcards(req_string)
        return nil if normalized.empty? || normalized == "*"

        matches = COMPARATOR_PATTERN.match(normalized)
        raise BadRequirementError, "Illformed requirement [#{req_string.inspect}]" unless matches

        minor_string = matches[:minor]
        patch_string = matches[:patch]
        minor = minor_string&.then { |value| value == "*" ? nil : value.to_i }
        patch = patch_string&.then { |value| value == "*" ? nil : value.to_i }
        operator = comparator_operator(matches[:operator], minor_string, patch_string)
        version_string = [matches[:major], minor || 0, patch || 0].join(".")
        version_string += matches[:prerelease].to_s
        version_string += matches[:build].to_s

        Comparator.new(
          operator: operator,
          major: T.must(matches[:major]).to_i,
          minor: minor,
          patch: patch,
          version: T.cast(Cargo::Version.new(version_string), Cargo::Version)
        )
      end

      sig do
        params(
          operator: T.nilable(String),
          minor: T.nilable(String),
          patch: T.nilable(String)
        ).returns(Symbol)
      end
      def comparator_operator(operator, minor, patch)
        return :wildcard if operator.nil? && (minor == "*" || patch == "*")

        case operator
        when nil, "^" then :caret
        when "=", "==" then :exact
        when ">" then :greater
        when ">=" then :greater_eq
        when "<" then :less
        when "<=" then :less_eq
        when "~" then :tilde
        else raise "Unknown Cargo comparator operator: #{operator}"
        end
      end

      sig { params(req_string: String).returns(T.any(String, T::Array[String])) }
      def convert_rust_constraint_to_ruby_constraint(req_string)
        req_string = normalize_wildcards(req_string)
        if req_string.include?("*")
          ruby_range(req_string.gsub(/(?:\.|^)[*]/, "").gsub(/^[^\d]/, ""))
        elsif req_string.match?(/^~[^>]/) then convert_tilde_req(req_string)
        elsif req_string.match?(/^[\d^]/) then convert_caret_req(req_string)
        elsif req_string.match?(/[<=>]/) then req_string
        else
          ruby_range(req_string)
        end
      end

      sig { params(req_string: String).returns(String) }
      def normalize_wildcards(req_string)
        req_string.sub(/\A[^-+]*/) { |release| release.tr("xX", "*") }
      end

      sig { params(req_string: String).returns(String) }
      def convert_tilde_req(req_string)
        version = req_string.gsub(/^~/, "")
        parts = version.split(".")
        parts << "0" if parts.count < 3
        "~> #{parts.join('.')}"
      end

      sig { params(req_string: String).returns(String) }
      def ruby_range(req_string)
        parts = req_string.split(".")

        # If we have three or more parts then this is an exact match
        return req_string if parts.count >= 3

        # If we have no parts then the version is completely unlocked
        return ">= 0" if parts.none?

        # If we have fewer than three parts we do a partial match
        parts << "0"
        "~> #{parts.join('.')}"
      end

      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_caret_req(req_string)
        version = req_string.gsub(/^\^/, "")
        parts = version.split(".")
        first_non_zero = parts.find { |d| d != "0" }
        first_non_zero_index =
          first_non_zero ? T.must(parts.index(first_non_zero)) : parts.count - 1
        upper_bound = parts.map.with_index do |part, i|
          if i < first_non_zero_index then part
          elsif i == first_non_zero_index then (part.to_i + 1).to_s
          else
            0
          end
        end.join(".")

        [">= #{version}", "< #{upper_bound}"]
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("cargo", Dependabot::Cargo::Requirement)
