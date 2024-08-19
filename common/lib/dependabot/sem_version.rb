# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# See https://semver.org/spec/v2.0.0.html for semver 2 details
#
module Dependabot
  class SemVersion
    extend T::Sig
    extend T::Helpers
    include Comparable

    SEMVER_REGEX = /^
      (0|[1-9]\d*)\. # major
      (0|[1-9]\d*)\. # minor
      (0|[1-9]\d*)   # patch
      (?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))? # pre release
      (?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))? # build metadata
    $/x

    sig { returns(String) }
    attr_accessor :major

    sig { returns(String) }
    attr_accessor :minor

    sig { returns(String) }
    attr_accessor :patch

    sig { returns(T.nilable(String)) }
    attr_accessor :build

    sig { returns(T.nilable(String)) }
    attr_accessor :prerelease

    sig { params(version: String).void }
    def initialize(version)
      tokens = parse(version)
      @major = T.let(T.must(tokens[:major]), String)
      @minor = T.let(T.must(tokens[:minor]), String)
      @patch = T.let(T.must(tokens[:patch]), String)
      @build = T.let(tokens[:build], T.nilable(String))
      @prerelease = T.let(tokens[:prerelease], T.nilable(String))
    end

    sig { returns(T::Boolean) }
    def prerelease?
      !!prerelease
    end

    sig { returns(String) }
    def to_s
      value = [major, minor, patch].join(".")
      value += "-#{prerelease}" if prerelease
      value += "+#{build}" if build
      value
    end

    sig { returns(String) }
    def inspect
      "#<#{self.class} #{self}>"
    end

    sig { params(other: ::Dependabot::SemVersion).returns(T::Boolean) }
    def eql?(other)
      other.is_a?(self.class) && to_s == other.to_s
    end

    sig { params(other: ::Dependabot::SemVersion).returns(Integer) }
    def <=>(other)
      maj = major.to_i <=> other.major.to_i
      return maj unless maj.zero?

      min = minor.to_i <=> other.minor.to_i
      return min unless min.zero?

      pat = patch.to_i <=> other.patch.to_i
      return pat unless pat.zero?

      pre = compare_prereleases(prerelease, other.prerelease)
      return pre unless pre.zero?

      0
    end

    sig { params(version: T.nilable(String)).returns(T::Boolean) }
    def self.correct?(version)
      return false if version.nil?

      version.match?(SEMVER_REGEX)
    end

    private

    sig { params(version: String).returns(T::Hash[Symbol, T.nilable(String)]) }
    def parse(version)
      match = version.match(SEMVER_REGEX)
      raise ArgumentError, "Malformed version number string #{version}" unless match

      major, minor, patch, prerelease, build = match.captures
      raise ArgumentError, "Malformed version number string #{version}" if minor.empty? || patch.empty?

      { major: major, minor: minor, patch: patch, prerelease: prerelease, build: build }
    end

    sig { params(prerelease1: T.nilable(String), prerelease2: T.nilable(String)).returns(Integer) }
    def compare_prereleases(prerelease1, prerelease2) # rubocop:disable Metrics/PerceivedComplexity
      return 0 if prerelease1.nil? && prerelease2.nil?
      return -1 if prerelease2.nil?
      return 1 if prerelease1.nil?

      prerelease1_tokens = prerelease1.split(".")
      prerelease2_tokens = prerelease2.split(".")

      prerelease1_tokens.zip(prerelease2_tokens) do |t1, t2|
        return 1 if t2.nil? # t2 can be nil, in which case it loses

        # If they're both ints, convert to such
        # If one's an int and the other isn't, the string version of the int gets correctly compared
        if t1 =~ /^\d+$/ && t2 =~ /^\d+$/
          t1 = t1.to_i
          t2 = t2.to_i
        end

        comp = t1 <=> t2
        return comp unless comp.zero?
      end

      # If we got this far, either they're equal (same length) or they won
      prerelease1_tokens.length == prerelease2_tokens.length ? 0 : -1
    end
  end
end
