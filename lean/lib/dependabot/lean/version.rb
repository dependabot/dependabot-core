# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Lean
    class Version < Dependabot::Version
      extend T::Sig

      # Matches versions like: 4.26.0, 4.26.0-rc1, 4.26.0-rc2
      VERSION_PATTERN = /\A(\d+)\.(\d+)\.(\d+)(?:-rc(\d+))?\z/

      sig { returns(Integer) }
      attr_reader :major

      sig { returns(Integer) }
      attr_reader :minor

      sig { returns(Integer) }
      attr_reader :patch

      sig { returns(T.nilable(Integer)) }
      attr_reader :rc

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        version_str = version.to_s.strip

        # Remove leading 'v' if present
        version_str = T.must(version_str[1..]) if version_str.start_with?("v")

        match = T.must(version_str.match(VERSION_PATTERN))

        @major = T.let(Integer(match[1]), Integer)
        @minor = T.let(Integer(match[2]), Integer)
        @patch = T.let(Integer(match[3]), Integer)
        @rc = T.let(match[4] ? Integer(match[4]) : nil, T.nilable(Integer))
        @version_string = T.let(version_str, String)

        super(@version_string)
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version_str = version.to_s.strip
        version_str = T.must(version_str[1..]) if version_str.start_with?("v")
        version_str.match?(VERSION_PATTERN)
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { returns(T::Boolean) }
      def prerelease?
        !@rc.nil?
      end

      sig { params(other: VersionParameter).returns(T.nilable(Integer)) }
      def <=>(other)
        other_version = case other
                        when Version then other
                        when Gem::Version then begin
                          Version.new(other.to_s)
                        rescue StandardError
                          nil
                        end
                        when String then begin
                          Version.new(other)
                        rescue StandardError
                          nil
                        end
                        end

        return nil unless other_version

        other_version = T.cast(other_version, Version)

        # Compare major.minor.patch first
        result = [@major, @minor, @patch] <=> [other_version.major, other_version.minor, other_version.patch]
        return result unless result.zero?

        # If major.minor.patch are equal, compare RC numbers
        # Non-RC (stable) versions are greater than RC versions
        # e.g., 4.26.0 > 4.26.0-rc2 > 4.26.0-rc1
        case [rc, other_version.rc]
        in [nil, nil] then 0
        in [nil, _] then 1      # self is stable, other is RC
        in [_, nil] then -1     # self is RC, other is stable
        else T.must(rc) <=> T.must(other_version.rc)
        end
      end
    end
  end
end

Dependabot::Utils.register_version_class("lean", Dependabot::Lean::Version)
