# typed: strong
# frozen_string_literal: true

require "dependabot/maven/version_parser"
require "dependabot/version"
require "dependabot/utils"

# See https://maven.apache.org/pom.html#Version_Order_Specification for details.

module Dependabot
  module Maven
    class Version < Dependabot::Version
      extend T::Sig
      extend T::Helpers

      PRERELEASE_QUALIFIERS = T.let(
        [
          Dependabot::Maven::VersionParser::ALPHA,
          Dependabot::Maven::VersionParser::BETA,
          Dependabot::Maven::VersionParser::MILESTONE,
          Dependabot::Maven::VersionParser::RC,
          Dependabot::Maven::VersionParser::SNAPSHOT
        ].freeze,
        T::Array[Integer]
      )

      VERSION_PATTERN =
        "[0-9a-zA-Z]+" \
        '(?>\.[0-9a-zA-Z]*)*' \
        '([_\-\+.][0-9A-Za-z]*)*'

      sig { returns(Dependabot::Maven::TokenBucket) }
      attr_accessor :token_bucket

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.to_s.empty?

        Dependabot::Maven::VersionParser.parse(version.to_s).to_a.any?
      rescue ArgumentError
        Dependabot.logger.info("Malformed version string #{version}")
        false
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        raise BadRequirementError, "Malformed version string - string is nil" if version.nil?

        @version_string = T.let(version.to_s, String)
        @token_bucket = T.let(Dependabot::Maven::VersionParser.parse(version_string), Dependabot::Maven::TokenBucket)
        super(version.to_s.tr("_", "-"))
      end

      sig { returns(String) }
      def inspect
        "#<#{self.class} #{version_string}>"
      end

      sig { returns(String) }
      def to_s
        version_string
      end

      sig { returns(T::Boolean) }
      def prerelease?
        token_bucket.to_a.flatten.any? do |token|
          token.is_a?(Integer) && token.negative?
        end
      end

      sig { returns(String) }
      def lowest_prerelease_suffix
        "a0"
      end

      sig { params(other: VersionParameter).returns(Integer) }
      def <=>(other)
        other = Dependabot::Maven::Version.new(other.to_s) unless other.is_a? Dependabot::Maven::Version
        T.must(token_bucket <=> T.cast(other, Dependabot::Maven::Version).token_bucket)
      end

      sig { override.returns(T::Array[String]) }
      def ignored_patch_versions
        parts = token_bucket.tokens # e.g [1,2,3] if version is 1.2.3-alpha3
        return [] if parts.empty? # for non-semver versions

        version_parts = T.let(parts.fill("0", parts.length...2), T::Array[Object])
        # the a0 is so we can get the next earliest prerelease patch version
        upper_parts = T.let(
          version_parts.first(1) + [numeric_token(version_parts[1]) + 1] + [lowest_prerelease_suffix],
          T::Array[Object]
        )
        lower_bound = "> #{to_semver}"
        upper_bound = "< #{upper_parts.join('.')}"

        ["#{lower_bound}, #{upper_bound}"]
      end

      sig { override.returns(T::Array[String]) }
      def ignored_minor_versions
        parts = token_bucket.tokens # e.g [1,2,3] if version is 1.2.3-alpha3
        return [] if parts.empty? # for non-semver versions

        version_parts = T.let(parts.fill("0", parts.length...2), T::Array[Object])
        lower_parts = T.let(
          version_parts.first(1) + [numeric_token(version_parts[1]) + 1] + [lowest_prerelease_suffix],
          T::Array[Object]
        )
        upper_parts = T.let(
          version_parts.first(0) + [numeric_token(version_parts[0]) + 1] + [lowest_prerelease_suffix],
          T::Array[Object]
        )
        lower_bound = ">= #{lower_parts.join('.')}"
        upper_bound = "< #{upper_parts.join('.')}"

        ["#{lower_bound}, #{upper_bound}"]
      end

      sig { override.returns(T::Array[String]) }
      def ignored_major_versions
        version_parts = token_bucket.tokens # e.g [1,2,3] if version is 1.2.3-alpha3
        return [] if version_parts.empty? # for non-semver versions

        lower_parts = T.let(
          [numeric_token(version_parts[0]) + 1] + [lowest_prerelease_suffix],
          T::Array[Object]
        ) # earliest next major version prerelease
        lower_bound = ">= #{lower_parts.join('.')}"

        [lower_bound]
      end

      private

      sig { returns(String) }
      attr_reader :version_string

      sig { params(token: Object).returns(Integer) }
      def numeric_token(token)
        token.to_s.to_i
      end
    end
  end
end

Dependabot::Utils.register_version_class("maven", Dependabot::Maven::Version)
