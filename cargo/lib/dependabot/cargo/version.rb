# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/version"
require "dependabot/utils"

# Rust pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.

module Dependabot
  module Cargo
    class Version < Dependabot::Version
      extend T::Sig

      VERSION_PATTERN = '[0-9]+(?>\.[0-9a-zA-Z]+)*' \
                        '(-[0-9A-Za-z-]+(\.[0-9a-zA-Z-]+)*)?' \
                        '(\+[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)?'
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        version = version.to_s.split("+").first if version.to_s.include?("+")

        super
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { override.returns(String) }
      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      sig { params(other: Object).returns(T.nilable(Integer)) }
      def <=>(other)
        return super unless other.is_a?(Cargo::Version)

        version_parts = semantic_version_parts(to_s)
        other_parts = semantic_version_parts(other.to_s)
        return super unless version_parts && other_parts

        release_comparison = compare_release(version_parts.first, other_parts.first)
        return release_comparison unless release_comparison.zero?

        compare_prerelease(version_parts.last, other_parts.last)
      end

      sig { params(other: Object).returns(T::Boolean) }
      def eql?(other)
        return super unless other.is_a?(Cargo::Version)

        version_parts = semantic_version_parts(to_s)
        other_parts = semantic_version_parts(other.to_s)
        return super unless version_parts || other_parts

        version_parts == other_parts
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      # Cargo uses a different semantic versioning approach for pre-1.0 versions:
      # - For 0.y.z versions: changes in y are considered major/breaking
      # - For 0.0.z versions: changes in z are considered major/breaking
      # - Only the leftmost non-zero component is considered for compatibility

      sig { override.returns(T::Array[String]) }
      def ignored_patch_versions
        parts = to_s.split(".")
        major = parts[0].to_i
        minor = parts[1].to_i

        # For 0.0.z versions, patch changes are breaking, so treat as major
        return ignored_major_versions if major.zero? && minor.zero?

        # For 0.y.z versions, patch changes are compatible, use standard logic
        return super if major.zero?

        # For 1.y.z+ versions, use standard semantic versioning
        super
      end

      sig { override.returns(T::Array[String]) }
      def ignored_minor_versions
        parts = to_s.split(".")
        major = parts[0].to_i

        # For 0.y.z versions, minor changes are breaking, so treat as major
        return ignored_major_versions if major.zero?

        # For 1.y.z+ versions, use standard semantic versioning
        super
      end

      sig { override.returns(T::Array[String]) }
      def ignored_major_versions
        parts = to_s.split(".")
        major = parts[0].to_i
        minor = parts[1].to_i

        # For 0.0.z versions, patch changes are breaking
        # So ignoring "major" means ignoring all >= 0.0.(z+1)
        if major.zero? && minor.zero?
          patch = parts[2].to_i
          lower_parts = [0, 0, patch + 1] + [lowest_prerelease_suffix]
          return [">= #{lower_parts.join('.')}"]
        end

        # For 0.y.z versions (y > 0), minor changes are breaking
        # So ignoring "major" means ignoring all >= 0.(y+1).0
        if major.zero?
          lower_parts = [0, minor + 1] + [lowest_prerelease_suffix]
          return [">= #{lower_parts.join('.')}"]
        end

        # For 1.y.z+ versions, use standard semantic versioning
        super
      end

      # Determines the correct update type for a version change according to Cargo's semantic versioning rules
      # For pre-1.0 versions, Cargo treats changes in the leftmost non-zero component as breaking
      sig do
        override
          .params(
            from_version: T.any(String, Dependabot::Cargo::Version),
            to_version: T.any(String, Dependabot::Cargo::Version)
          )
          .returns(String)
      end
      def self.update_type(from_version, to_version)
        from_v, to_v = normalize_versions(from_version, to_version)
        from_major, from_minor, from_patch, to_major, to_minor, to_patch = extract_version_parts(from_v, to_v)

        # Standard semver for 1.0.0+ versions
        return standard_semver_type(from_major, from_minor, from_patch, to_major, to_minor, to_patch) if from_major >= 1

        # Cargo pre-1.0 semver rules
        cargo_pre_1_0_type(from_major, from_minor, from_patch, to_major, to_minor, to_patch)
      rescue StandardError => e
        # Log the error but return a safe default
        Dependabot.logger.warn("Error in Cargo::Version.update_type: #{e.message}")
        "major" # Default to major for safety
      end

      sig do
        params(
          from_version: T.any(String, Dependabot::Cargo::Version),
          to_version: T.any(String, Dependabot::Cargo::Version)
        ).returns([Dependabot::Cargo::Version, Dependabot::Cargo::Version])
      end
      def self.normalize_versions(from_version, to_version)
        from_v = from_version.is_a?(String) ? T.cast(new(from_version), Dependabot::Cargo::Version) : from_version
        to_v = to_version.is_a?(String) ? T.cast(new(to_version), Dependabot::Cargo::Version) : to_version
        [from_v, to_v]
      end

      sig { params(from_v: Dependabot::Cargo::Version, to_v: Dependabot::Cargo::Version).returns([Integer, Integer, Integer, Integer, Integer, Integer]) }
      def self.extract_version_parts(from_v, to_v)
        from_parts = from_v.to_s.split(".").map(&:to_i)
        to_parts = to_v.to_s.split(".").map(&:to_i)

        [from_parts[0] || 0, from_parts[1] || 0, from_parts[2] || 0,
         to_parts[0] || 0, to_parts[1] || 0, to_parts[2] || 0]
      end

      # rubocop:disable Metrics/ParameterLists
      sig do
        params(
          from_major: Integer,
          from_minor: Integer,
          from_patch: Integer,
          to_major: Integer,
          to_minor: Integer,
          to_patch: Integer
        ).returns(String)
      end
      def self.standard_semver_type(from_major, from_minor, from_patch, to_major, to_minor, to_patch)
        return "major" if to_major > from_major
        return "minor" if to_minor > from_minor
        return "patch" if to_patch > from_patch

        "patch"
      end

      sig do
        params(
          from_major: Integer,
          from_minor: Integer,
          from_patch: Integer,
          to_major: Integer,
          to_minor: Integer,
          to_patch: Integer
        ).returns(String)
      end
      def self.cargo_pre_1_0_type(from_major, from_minor, from_patch, to_major, to_minor, to_patch)
        # Any major version increase is always major
        return "major" if to_major > from_major

        # For 0.0.z versions, any change is breaking
        return "major" if from_minor.zero? && (to_minor > from_minor || to_patch > from_patch)

        # For 0.y.z versions, minor changes are breaking
        return "major" if to_minor > from_minor

        # Only patch changes remain
        "patch"
      end
      # rubocop:enable Metrics/ParameterLists

      private

      sig { params(version_string: String).returns(T.nilable([T::Array[Integer], T.nilable(T::Array[String])])) }
      def semantic_version_parts(version_string)
        matches = SEMVER_REGEX.match(version_string)
        return unless matches

        release = [T.must(matches[1]).to_i, T.must(matches[2]).to_i, T.must(matches[3]).to_i]
        prerelease = matches[4]&.split(".")
        [release, prerelease]
      end

      sig { params(left: T::Array[Integer], right: T::Array[Integer]).returns(Integer) }
      def compare_release(left, right)
        left.each_with_index do |component, index|
          comparison = component <=> T.must(right[index])
          return comparison unless comparison.zero?
        end

        0
      end

      sig do
        params(
          left: T.nilable(T::Array[String]),
          right: T.nilable(T::Array[String])
        ).returns(Integer)
      end
      def compare_prerelease(left, right)
        return 0 unless left || right
        return 1 unless left
        return -1 unless right

        left.each_with_index do |identifier, index|
          right_identifier = right[index]
          return 1 unless right_identifier

          comparison = compare_prerelease_identifier(identifier, right_identifier)
          return comparison unless comparison.zero?
        end

        left.length <=> right.length
      end

      sig { params(left: String, right: String).returns(Integer) }
      def compare_prerelease_identifier(left, right)
        left_numeric = left.match?(/\A\d+\z/)
        right_numeric = right.match?(/\A\d+\z/)

        return left.to_i <=> right.to_i if left_numeric && right_numeric
        return -1 if left_numeric
        return 1 if right_numeric

        T.must(left <=> right)
      end
    end
  end
end

Dependabot::Utils.register_version_class("cargo", Dependabot::Cargo::Version)
