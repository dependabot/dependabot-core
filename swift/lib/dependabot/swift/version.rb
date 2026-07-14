# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module Swift
    # Swift uses SemVer: strict validation in .correct?, section 11 pre-release precedence in #<=>.
    # #initialize stays tolerant because GitCommitChecker builds unchecked versions (e.g. "0.0.0.0").
    class Version < Dependabot::Version
      extend T::Sig

      # SEMVER_REGEX uses ^/$ line anchors; anchor to the whole string to reject multiline.
      SEMVER_ANCHORED = T.let(/\A#{SEMVER_REGEX.source}\z/x, Regexp)

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        # Strict SemVer only: rejects "1.0.0.alpha", "0.0.0.0", "01.2.3" and multiline input.
        version.to_s.delete_prefix("v").match?(SEMVER_ANCHORED)
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s.dup.freeze, String)

        stripped = version.to_s.delete_prefix("v")
        pre_part, plus, build = stripped.partition("+")
        # Strip only well-formed build metadata (SemVer rule 10 ignores it); a malformed "+…" tail is
        # kept so it stays distinct and sorts below the release instead of canonicalizing to it.
        build_ok = plus.empty? || build.match?(/\A[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*\z/)
        @semver = T.let((build_ok ? pre_part : stripped).freeze, String)

        base, suffix = pre_part.split("-", 2)
        # Split on "-" only when the core before it is numeric (else the hyphen is part of the tail).
        if suffix && !base.to_s.match?(/\A[0-9]+(?:\.[0-9]+)*\z/)
          base = pre_part
          suffix = nil
        end
        release, inferred = normalize_release(T.must(base))
        suffix ||= inferred
        # Fold a malformed build tail into the pre-release suffix so it stays distinct and orderable.
        suffix = [suffix, "+#{build}"].compact.join(".") unless build_ok
        @prerelease_suffix = T.let(suffix, T.nilable(String))
        @release_core = T.let(Gem::Version.new(release), Gem::Version)
        # Seed the superclass with a strict-SemVer form so tolerant tags never raise, while mixed
        # comparisons still see the pre-release state.
        super(semver_seed(release, @prerelease_suffix))
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { override.returns(String) }
      def to_semver
        @semver
      end

      sig { returns(Gem::Version) }
      def bump
        # Bump the full-precision release core so "~>" bounds ignore the padded 3-segment seed.
        @release_core.bump
      end

      sig { override.returns(T::Boolean) }
      def prerelease?
        return true unless @prerelease_suffix.nil?

        super
      end

      # Strict-SemVer range with "-0" bounds (earliest prerelease) so the grammar accepts it.
      sig { override.returns(T::Array[String]) }
      def ignored_minor_versions
        parts = to_semver.split(".")
        major = parts[0].to_i
        minor = parts.fetch(1, 0).to_i
        [">= #{major}.#{minor + 1}.0-0, < #{major + 1}.0.0-0"]
      end

      # Strict-SemVer floor at "-0" (earliest prerelease) so a semver-major ignore covers numeric prereleases too.
      sig { override.returns(T::Array[String]) }
      def ignored_major_versions
        major = T.must(to_semver.split(".").first).to_i
        [">= #{major + 1}.0.0-0"]
      end

      sig { params(other: Object).returns(T::Boolean) }
      def eql?(other)
        return false unless other.is_a?(Version)

        to_semver == other.to_semver
      end

      sig { override.returns(Integer) }
      def hash
        to_semver.hash
      end

      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        cmp = self <=> other
        !cmp.nil? && cmp.zero?
      end

      sig { params(other: Object).returns(T.nilable(Integer)) }
      def <=>(other)
        return nil if other.nil?

        resolved = coerce_operand(other)
        return nil if resolved.nil?

        # Compare release cores directly (not via super, whose seeded state uses RubyGems
        # pre-release ordering) so section 11 governs the pre-release tiebreak.
        release_cmp = release_core <=> resolved.release_core
        return release_cmp unless release_cmp&.zero?

        compare_semver_prerelease(@prerelease_suffix, resolved.prerelease_suffix)
      rescue ArgumentError
        nil
      end

      protected

      sig { returns(T.nilable(String)) }
      attr_reader :prerelease_suffix

      sig { returns(Gem::Version) }
      attr_reader :release_core

      private

      # Coerce an operand to a Swift::Version for section 11 ordering, or nil if not orderable.
      # A raw Gem::Version pre-release is declined (lossy #to_s, divergent RubyGems ordering); any
      # #to_s failure also yields nil to keep comparison safe (never raises).
      sig { params(other: Object).returns(T.nilable(Version)) }
      def coerce_operand(other)
        return other if other.is_a?(Version)
        return nil if other.is_a?(Gem::Version) && other.prerelease?

        normalized = other.to_s.delete_prefix("v")
        if normalized.include?("+")
          return nil unless Version.correct?(normalized)

          normalized = T.must(normalized.split("+").first)
        end
        return nil unless Gem::Version.correct?(normalized)

        T.cast(Version.new(normalized), Version)
      rescue StandardError
        nil
      end

      # Returns [release core, inferred pre-release or nil]: a non-SemVer tag is reduced to its
      # numeric core with the non-numeric tail as pre-release ("1.0.0.alpha" -> "alpha").
      sig { params(base: String).returns([String, T.nilable(String)]) }
      def normalize_release(base)
        return [base, nil] if self.class.correct?(base)

        parts = base.split(".")
        numeric = parts.take_while { |s| s.match?(/\A\d+\z/) }
        raise ArgumentError, "Malformed version number string #{@version_string}" if numeric.empty?

        tail = parts.drop(numeric.length)
        # Preserve every numeric segment so multi-segment requirement bounds keep full precision.
        release = numeric.map { |s| s.to_i.to_s }.join(".")
        [release, tail.empty? ? nil : tail.join(".")]
      end

      # Strict-SemVer seed for the Gem superclass: Gem::Version#initialize validates via
      # self.class.correct? (strict 3-part SemVer here), so the seed is a 3-segment core plus the
      # suffix only when it is valid SemVer, letting tolerant tags (e.g. "0.0.0.0") never raise.
      sig { params(release: String, suffix: T.nilable(String)).returns(String) }
      def semver_seed(release, suffix)
        core = (release.split(".").first(3) + %w(0 0 0)).first(3).join(".")
        return core unless suffix && self.class.correct?("0.0.0-#{suffix}")

        "#{core}-#{suffix}"
      end

      # SemVer section 11 pre-release precedence: 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0.
      sig { params(left: T.nilable(String), right: T.nilable(String)).returns(Integer) }
      def compare_semver_prerelease(left, right)
        return 0 if left.nil? && right.nil?
        return 1 if left.nil?
        return -1 if right.nil?

        left_ids = left.split(".")
        right_ids = right.split(".")

        # Compare identifiers pairwise over the common prefix.
        [left_ids.length, right_ids.length].min.times do |i|
          cmp = compare_semver_identifier(T.must(left_ids[i]), T.must(right_ids[i]))
          return cmp unless cmp.zero?
        end

        # All shared identifiers equal: more pre-release fields ranks higher.
        left_ids.length <=> right_ids.length
      end

      sig { params(left: String, right: String).returns(Integer) }
      def compare_semver_identifier(left, right)
        left_numeric = left.match?(/\A\d+\z/)
        right_numeric = right.match?(/\A\d+\z/)

        if left_numeric && right_numeric
          cmp = left.to_i <=> right.to_i
          # Tiebreak textually so SemVer-invalid leading-zero ids ("01" vs "1") stay distinct.
          cmp.zero? ? T.must(left <=> right) : cmp
        elsif left_numeric
          -1
        elsif right_numeric
          1
        else
          T.must(left <=> right)
        end
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("swift", Dependabot::Swift::Version)
