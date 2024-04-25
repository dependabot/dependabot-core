# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"
require "sorbet-runtime"

# Dotnet pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
# Dotnet also supports build versions, separated with a "+".
module Dependabot
  module Nuget
    class Version < Dependabot::Version
      extend T::Sig

      VERSION_PATTERN = T.let(Gem::Version::VERSION_PATTERN + '(\+[0-9a-zA-Z\-.\*]+)?', String)
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        version = version.to_s.split("+").first || ""
        @version_string = T.let(version, String)

        super
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Nuget::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Nuget::Version)
      end

      sig { returns(String) }
      def to_s
        @version_string
      end

      sig { returns(String) }
      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      sig { params(other: Object).returns(Integer) }
      def <=>(other)
        version_comparison = compare_release(other)
        return version_comparison unless version_comparison.zero?

        compare_prerelease_part(other)
      end

      sig { params(other: Object).returns(Integer) }
      def compare_release(other)
        release_str = @version_string.split("-").first || ""
        other_release_str = other.to_s.split("-").first || ""

        T.must(Gem::Version.new(release_str) <=> Gem::Version.new(other_release_str))
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(other: Object).returns(Integer) }
      def compare_prerelease_part(other)
        release_str = @version_string.split("-").first || ""
        prerelease_string = @version_string
                            .sub(release_str, "")
                            .sub("-", "")
        prerelease_string = nil if prerelease_string == ""

        other_release_str = other.to_s.split("-").first || ""
        other_prerelease_string = other.to_s
                                       .sub(other_release_str, "")
                                       .sub("-", "")
        other_prerelease_string = nil if other_prerelease_string == ""

        return -1 if prerelease_string && !other_prerelease_string
        return 1 if !prerelease_string && other_prerelease_string
        return 0 if !prerelease_string && !other_prerelease_string

        split_prerelease_string = T.must(prerelease_string).split(".")
        other_split_prerelease_string = T.must(other_prerelease_string).split(".")

        length = [split_prerelease_string.length, other_split_prerelease_string.length].max - 1
        (0..length).to_a.each do |index|
          lhs = split_prerelease_string[index]
          rhs = other_split_prerelease_string[index]
          result = compare_dot_separated_part(lhs, rhs)
          return result unless result.zero?
        end

        0
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(lhs: T.nilable(String), rhs: T.nilable(String)).returns(Integer) }
      def compare_dot_separated_part(lhs, rhs)
        return -1 if lhs.nil?
        return 1 if rhs.nil?

        return lhs.to_i <=> rhs.to_i if lhs.match?(/^\d+$/) && rhs.match?(/^\d+$/)

        T.must(lhs.upcase <=> rhs.upcase)
      end
    end
  end
end

Dependabot::Utils.register_version_class("nuget", Dependabot::Nuget::Version)
