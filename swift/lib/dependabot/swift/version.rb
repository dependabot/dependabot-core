# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"
require "dependabot/version/semver_prerelease_comparison"

module Dependabot
  module Swift
    class Version < Dependabot::Version
      extend T::Sig
      include Dependabot::Version::SemverPrereleaseComparison

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        v = version.to_s.delete_prefix("v")
        return false if v.empty?

        v.match?(SEMVER_REGEX) || Gem::Version.correct?(v) == true
      end

      sig { params(version: VersionParameter).returns(T::Boolean) }
      def self.semver?(version)
        return false if version.nil?

        version.to_s.delete_prefix("v").match?(SEMVER_REGEX)
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        @prerelease_suffix = T.let(nil, T.nilable(String))

        v = version.to_s.delete_prefix("v")
        v = T.must(v.split("+").first) if v.include?("+")
        if v.include?("-")
          parts = v.split("-", 2)
          v = T.must(parts[0])
          @prerelease_suffix = parts[1]
        end

        super(v)
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { override.returns(String) }
      def to_semver
        str = @version_string.delete_prefix("v")
        str.split("+").first || str
      end

      sig { override.returns(T::Boolean) }
      def prerelease?
        !@prerelease_suffix.nil?
      end

      sig { params(other: Object).returns(T::Boolean) }
      def eql?(other)
        return false unless other.is_a?(Version)

        to_semver == other.to_semver
      end

      sig { override.returns(Integer) }
      def hash
        to_semver.hash
      end

      sig { params(other: Object).returns(T.nilable(Integer)) }
      def <=>(other)
        return nil if other.nil?

        unless other.is_a?(Version)
          return nil unless self.class.correct?(other.to_s)

          other = self.class.new(other.to_s)
        end

        result = super
        return result if result.nil? || !result.zero?

        compare_semver_prerelease(@prerelease_suffix, T.cast(other, Version).prerelease_suffix)
      rescue ArgumentError
        nil
      end

      protected

      sig { returns(T.nilable(String)) }
      attr_reader :prerelease_suffix
    end
  end
end

Dependabot::Utils
  .register_version_class("swift", Dependabot::Swift::Version)
