# typed: strict
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"
require "sorbet-runtime"

# Deno uses semver for both jsr: and npm: specifiers.
# Build metadata (e.g. 1.0.0+build) is preserved but ignored in comparisons.

module Dependabot
  module Deno
    class Version < Dependabot::Version
      extend T::Sig

      VERSION_PATTERN = T.let(Gem::Version::VERSION_PATTERN + '(\+[0-9a-zA-Z\-.]+)?', String)
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

      sig { returns(T.nilable(String)) }
      attr_reader :build_info

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        @build_info = T.let(nil, T.nilable(String))

        version, @build_info = version.to_s.split("+") if version.to_s.include?("+")

        super(T.must(version))
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Deno::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Deno::Version)
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { override.returns(String) }
      def inspect
        "#<#{self.class} #{@version_string}>"
      end
    end
  end
end

Dependabot::Utils.register_version_class("deno", Dependabot::Deno::Version)
