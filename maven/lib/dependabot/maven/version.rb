# typed: strict
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

      PRERELEASE_QUALIFIERS = T.let([
        Dependabot::Maven::VersionParser::ALPHA,
        Dependabot::Maven::VersionParser::BETA,
        Dependabot::Maven::VersionParser::MILESTONE,
        Dependabot::Maven::VersionParser::RC,
        Dependabot::Maven::VersionParser::SNAPSHOT
      ].freeze, T::Array[Integer])

      VERSION_PATTERN =
        "[0-9a-zA-Z]+" \
        '(?>\.[0-9a-zA-Z]*)*' \
        '([_\-\+][0-9A-Za-z_-]*(\.[0-9A-Za-z_-]*)*)?'

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
        @version_string = T.let(version.to_s, String)
        @token_bucket = T.let(Dependabot::Maven::VersionParser.parse(version_string), Dependabot::Maven::TokenBucket)
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

      sig { params(other: VersionParameter).returns(Integer) }
      def <=>(other)
        other = Dependabot::Maven::Version.new(other.to_s) unless other.is_a? Dependabot::Maven::Version
        T.must(token_bucket <=> T.cast(other, Dependabot::Maven::Version).token_bucket)
      end

      sig { returns(Integer) }
      def hash
        token_bucket.hash
      end

      private

      sig { returns(String) }
      attr_reader :version_string
    end
  end
end

Dependabot::Utils.register_version_class("maven", Dependabot::Maven::Version)
