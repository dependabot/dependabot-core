# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# See https://semver.org/spec/v2.0.0.html for semver 2 details
#
module Dependabot
  class SemVersion2
    extend T::Sig
    extend T::Helpers
    include Comparable

    SEMVER2_REGEX = /^
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

    sig { params(other: ::Dependabot::SemVersion2).returns(T::Boolean) }
    def eql?(other)
      other.is_a?(self.class) && to_s == other.to_s
    end

    sig { params(other: ::Dependabot::SemVersion2).returns(Integer) }
    def <=>(other)
      result = major.to_i <=> other.major.to_i
      return result unless result.zero?

      result = minor.to_i <=> other.minor.to_i
      return result unless result.zero?

      result = patch.to_i <=> other.patch.to_i
      return result unless result.zero?

      compare_prereleases(prerelease, other.prerelease)
    end

    sig { params(version: T.nilable(String)).returns(T::Boolean) }
    def self.correct?(version)
      return false if version.nil?

      version.match?(SEMVER2_REGEX)
    end

    private

    sig { params(version: String).returns(T::Hash[Symbol, T.nilable(String)]) }
    def parse(version)
      match = version.match(SEMVER2_REGEX)
      raise ArgumentError, "Malformed version number string #{version}" unless match

      major, minor, patch, prerelease, build = match.captures

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
        return 1 if t2.nil? # t1 is more specific e.g. 1.0.0-rc1.1 vs 1.0.0-rc1

        if t1 =~ /^\d+$/ && t2 =~ /^\d+$/
          # t1 and t2 are both ints so compare them as such
          a = t1.to_i
          b = t2.to_i
          compare = a <=> b
          return compare unless compare.zero?
        end

        comp = t1 <=> t2
        return T.must(comp) unless T.must(comp).zero?
      end

      # prereleases are equal or prerelease2 is more specific e.g. 1.0.0-rc1 vs 1.0.0-rc1.1
      prerelease1_tokens.length == prerelease2_tokens.length ? 0 : -1
    end
  end
end
