# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Version < Gem::Version
    extend T::Sig
    extend T::Helpers

    abstract!

    VersionParameter = T.type_alias { T.nilable(T.any(String, Integer, Gem::Version)) }

    sig { override.overridable.params(version: VersionParameter).void }
    def initialize(version)
      @original_version = T.let(version.to_s, String)

      super
    end

    sig { override.overridable.params(version: VersionParameter).returns(Dependabot::Version) }
    def self.new(version)
      T.cast(super, Dependabot::Version)
    end

    # Opt-in to Rubygems 4 behavior
    sig { override.overridable.params(version: VersionParameter).returns(T::Boolean) }
    def self.correct?(version)
      return false if version.nil?

      version.to_s.match?(ANCHORED_VERSION_PATTERN)
    end

    sig { overridable.returns(String) }
    def to_semver
      @original_version
    end

    sig { overridable.returns(T::Array[String]) }
    def ignored_patch_versions
      parts = to_semver.split(".")
      version_parts = parts.fill("0", parts.length...2)
      upper_parts = version_parts.first(1) + [version_parts[1].to_i + 1]
      lower_bound = "> #{to_semver}"
      upper_bound = "< #{upper_parts.join('.')}"

      ["#{lower_bound}, #{upper_bound}"]
    end

    sig { overridable.returns(T::Array[String]) }
    def ignored_minor_versions
      parts = to_semver.split(".")
      version_parts = parts.fill("0", parts.length...2)
      lower_parts = version_parts.first(1) + [version_parts[1].to_i + 1] + [lowest_prerelease_suffix]
      upper_parts = version_parts.first(0) + [version_parts[0].to_i + 1]
      lower_bound = ">= #{lower_parts.join('.')}"
      upper_bound = "< #{upper_parts.join('.')}"

      ["#{lower_bound}, #{upper_bound}"]
    end

    sig { overridable.returns(T::Array[String]) }
    def ignored_major_versions
      version_parts = to_semver.split(".")
      lower_parts = [version_parts[0].to_i + 1] + [lowest_prerelease_suffix]
      lower_bound = ">= #{lower_parts.join('.')}"

      [lower_bound]
    end

    sig { returns(String) }
    def lowest_prerelease_suffix
      "a"
    end

    sig { returns(T.nilable([Integer, Integer, Integer])) }
    def semver_parts
      # Extracts only the numeric major.minor.patch part of the version, ensuring it starts with a number
      match = to_semver.match(/^\d+(?:\.\d+)?(?:\.\d+)?(?=[^\d]|$)/)
      return nil unless match

      first_match = match[0]
      return nil unless first_match

      major, minor, patch = first_match.split(".").map(&:to_i)
      [major || 0, minor || 0, patch || 0]
    end
  end
end
