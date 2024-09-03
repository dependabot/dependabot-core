# typed: true
# frozen_string_literal: true

require "dependabot/maven/version_parser"
require "dependabot/version"
require "dependabot/utils"

# See https://maven.apache.org/pom.html#Version_Order_Specification for details.

module Dependabot
  module Maven
    class NewVersion < Dependabot::Version
      PRERELEASE_QUALIFIERS = [
        Dependabot::Maven::VersionParser::ALPHA,
        Dependabot::Maven::VersionParser::BETA,
        Dependabot::Maven::VersionParser::MILESTONE,
        Dependabot::Maven::VersionParser::RC,
        Dependabot::Maven::VersionParser::SNAPSHOT
      ].freeze

      attr_accessor :bucket

      def self.correct?(version)
        return false if version.nil? || version.empty?

        Dependabot::Maven::VersionParser.parse(version.to_s).any?
      end

      def initialize(version)
        @version_string = version.to_s
        @bucket = Dependabot::Maven::VersionParser.parse(version.to_s)
      end

      def inspect
        "#<#{self.class} #{@version_string}>"
      end

      def to_s
        @version_string
      end

      def prerelease?
        bucket.to_a.flatten.any? do |token|
          token.is_a?(Integer) && token.negative?
        end
      end

      def <=>(other)
        bucket <=> other.bucket
      end
    end
  end
end

Dependabot::Utils.register_version_class("maven", Dependabot::Maven::NewVersion)
