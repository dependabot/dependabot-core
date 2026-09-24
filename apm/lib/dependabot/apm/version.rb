# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module Apm
    # APM pins dependencies to git refs. When that ref is a SemVer 2.0.0 tag
    # (optionally `v`-prefixed, e.g. `v1.2.0`, `1.2.0-alpha.1` or `1.2.0+build.5`)
    # we treat it as the dependency version.
    #
    # The parent class uses RubyGems semantics, which differ from SemVer in ways
    # that matter for git tags, so this subclass enforces SemVer 2.0.0 instead:
    #   * validation requires MAJOR.MINOR.PATCH, so partial refs (`v1`, `1.2`) or
    #     branch names are never mistaken for versions;
    #   * `+build` metadata is accepted and ignored for precedence;
    #   * prerelease identifiers follow SemVer precedence (numeric identifiers
    #     rank below alphanumeric ones, so `1.0.0-alpha.1 < 1.0.0-alpha.beta` —
    #     the opposite of RubyGems, which compares them the other way around).
    class Version < Dependabot::Version
      extend T::Sig

      # Official SemVer 2.0.0 grammar (https://semver.org), anchored end to end so
      # partial or branch-like refs are rejected.
      SEMVER_REGEX = /
        \A
        (?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)
        (?:-(?<prerelease>
          (?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)
          (?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*
        ))?
        (?:\+(?<build>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?
        \z
      /x

      sig { returns(Integer) }
      attr_reader :major

      sig { returns(Integer) }
      attr_reader :minor

      sig { returns(Integer) }
      attr_reader :patch

      sig { returns(T.nilable(String)) }
      attr_reader :prerelease_info

      sig { returns(T.nilable(String)) }
      attr_reader :build_info

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        normalized = Version.remove_leading_v(version).to_s
        match = normalized.match(SEMVER_REGEX)
        raise ArgumentError, "Malformed version string - #{version}" unless match

        @version_string = T.let(normalized, String)
        @major = T.let(T.must(match[:major]).to_i, Integer)
        @minor = T.let(T.must(match[:minor]).to_i, Integer)
        @patch = T.let(T.must(match[:patch]).to_i, Integer)
        @prerelease_info = T.let(match[:prerelease], T.nilable(String))
        @build_info = T.let(match[:build], T.nilable(String))

        # Hand RubyGems the release (plus any prerelease) without the build
        # metadata, which is not part of precedence, so requirement matching and
        # the inherited helpers keep working.
        super(T.must(normalized.split("+").first))
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Apm::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Apm::Version)
      end

      sig { params(version: VersionParameter).returns(VersionParameter) }
      def self.remove_leading_v(version)
        return version unless version.to_s.match?(/\Av\d/)

        version.to_s.delete_prefix("v")
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.to_s.strip.empty?

        Version.remove_leading_v(version).to_s.match?(SEMVER_REGEX)
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { override.returns(String) }
      def inspect
        "#<#{self.class} #{@version_string}>"
      end

      # `Gem::Requirement` evaluates a `~> x.y.z` bound by comparing candidates
      # against this operand's `bump`. The inherited `Gem::Version#bump` drops
      # the last segment (`1.2.3` -> `1.3`) and rebuilds `self.class` from it,
      # but `Apm::Version` rejects that partial value and raises while filtering
      # tags. Return the SemVer upper bound (`x.(y+1).0`) instead, so a
      # pessimistic ignore rule such as `~> 1.2.3` evaluates as
      # `>= 1.2.3, < 1.3.0` rather than crashing.
      sig { returns(Dependabot::Apm::Version) }
      def bump
        Version.new("#{major}.#{minor + 1}.0")
      end

      sig { params(other: Object).returns(T.nilable(Integer)) }
      def <=>(other)
        other_version = Version.coerce(other)
        return super unless other_version

        release = compare_release(other_version)
        return release unless release.zero?

        Version.compare_prerelease(prerelease_info, other_version.prerelease_info)
      end

      # Compares the MAJOR.MINOR.PATCH triples numerically.
      sig { params(other: Dependabot::Apm::Version).returns(Integer) }
      def compare_release(other)
        [[major, other.major], [minor, other.minor], [patch, other.patch]].each do |mine, theirs|
          comparison = mine <=> theirs
          return comparison unless comparison.zero?
        end

        0
      end

      # Coerces a comparison operand into an Apm::Version when it is a strict
      # SemVer value, or nil when it is not (so `<=>` can fall back to RubyGems
      # semantics for e.g. a bare `Gem::Version` requirement bound).
      sig { params(other: Object).returns(T.nilable(Dependabot::Apm::Version)) }
      def self.coerce(other)
        return other if other.is_a?(Dependabot::Apm::Version)
        return unless other.is_a?(String) || other.is_a?(Gem::Version)
        return unless correct?(other.to_s)

        new(other.to_s)
      end

      # SemVer prerelease precedence (spec rule 11): a version WITH a prerelease
      # ranks below the same version without one, and equal releases are ordered
      # by their prerelease identifiers.
      sig { params(left: T.nilable(String), right: T.nilable(String)).returns(Integer) }
      def self.compare_prerelease(left, right)
        return 0 if left == right
        return 1 if left.nil? # a normal version outranks any prerelease
        return -1 if right.nil?

        compare_prerelease_identifiers(left.split("."), right.split("."))
      end

      # Compares dot-separated prerelease identifiers left to right; a longer set
      # of identifiers wins when the shorter one is a prefix of it.
      sig { params(left: T::Array[String], right: T::Array[String]).returns(Integer) }
      def self.compare_prerelease_identifiers(left, right)
        left.zip(right).each do |l, r|
          return 1 if r.nil? # left carries an extra identifier

          comparison = compare_identifier(l, r)
          return comparison unless comparison.zero?
        end

        left.length <=> right.length
      end

      # A single prerelease identifier: numeric identifiers compare numerically
      # and always rank below alphanumeric ones, which compare lexically (ASCII).
      sig { params(left: String, right: String).returns(Integer) }
      def self.compare_identifier(left, right)
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

Dependabot::Utils
  .register_version_class("apm", Dependabot::Apm::Version)
