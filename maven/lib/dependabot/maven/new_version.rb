# typed: strict
# frozen_string_literal: true

require "dependabot/maven/version_parser"
require "dependabot/version"
require "dependabot/utils"

# See https://maven.apache.org/pom.html#Version_Order_Specification for details.

module Dependabot
  module Maven
    class NewVersion
      extend T::Sig
      extend T::Helpers

      PRERELEASE_QUALIFIERS = T.let([
        Dependabot::Maven::VersionParser::ALPHA,
        Dependabot::Maven::VersionParser::BETA,
        Dependabot::Maven::VersionParser::MILESTONE,
        Dependabot::Maven::VersionParser::RC,
        Dependabot::Maven::VersionParser::SNAPSHOT
      ].freeze, T::Array[Integer])

      sig { returns(Dependabot::Maven::TokenBucket) }
      attr_accessor :token_bucket

      sig { params(version: String).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.empty?

        Dependabot::Maven::VersionParser.parse(version.to_s).to_a.any?
      rescue Dependabot::BadRequirementError
        Dependabot.logger.info("Malformed version string - #{version}")
        false
      end

      sig { params(version: String).void }
      def initialize(version)
        @version_string = T.let(version, String)
        @token_bucket = T.let(Dependabot::Maven::VersionParser.parse(version), Dependabot::Maven::TokenBucket)
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

      sig { params(other: ::Dependabot::Maven::NewVersion).returns(Integer) }
      def <=>(other)
        T.must(token_bucket <=> other.token_bucket)
      end

      private

      sig { returns(String) }
      attr_reader :version_string
    end
  end
end
