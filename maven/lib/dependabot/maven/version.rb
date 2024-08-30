# typed: true
# frozen_string_literal: true

require "dependabot/maven/version_parser"
require "dependabot/version"
require "dependabot/utils"

# See https://maven.apache.org/pom.html#Version_Order_Specification for details.

module Dependabot
  module Maven
    class Version < Dependabot::Version
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
        tokens.to_a.flatten.any? do |token|
          token.is_a?(Integer) && token.negative?
        end
      end

      def <=>(other)
        bucket <=> other.bucket
        # cmp = compare_tokens(bucket.tokens, other.bucket.tokens)
        # return cmp unless cmp.zero?

        # compare_additions(bucket.addition, other.bucket.addition)
      end

      private

      def compare_tokens(a, b) # rubocop:disable Naming/MethodParameterName
        max_idx = [a.size, b.size].max - 1
        (0..max_idx).each do |idx|
          cmp = compare_token_pair(a[idx], b[idx])
          return cmp unless cmp.zero?
        end
        0
      end

      def compare_token_pair(a = 0, b = 0) # rubocop:disable Metrics/PerceivedComplexity
        a ||= 0
        b ||= 0

        if a.is_a?(Integer) && b.is_a?(String)
          return a <= 0 ? -1 : 1
        end

        if a.is_a?(String) && b.is_a?(Integer)
          return b <= 0 ? 1 : -1
        end

        if a == Dependabot::Maven::VersionParser::SP && b.is_a?(String) && b != Dependabot::Maven::VersionParser::SP
          return -1
        end

        if b == Dependabot::Maven::VersionParser::SP && a.is_a?(String) && a != Dependabot::Maven::VersionParser::SP
          return 1
        end

        a <=> b # a and b are both ints or strings
      end

      def compare_additions(first, second)
        return 0 if first.nil? && second.nil?

        (first || empty_addition) <=> (second || empty_addition)
      end

      def empty_addition
        TokenBucket.new([])
      end
    end
  end
end

Dependabot::Utils.register_version_class("maven", Dependabot::Maven::Version)
