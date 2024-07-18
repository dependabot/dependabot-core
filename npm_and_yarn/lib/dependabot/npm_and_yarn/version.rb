# typed: strict
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"
require "sorbet-runtime"

# JavaScript pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
#
# See https://semver.org/ for details of node's version syntax.

module Dependabot
  module NpmAndYarn
    class Version < Dependabot::Version
      extend T::Sig

      sig { returns(T.nilable(String)) }
      attr_reader :build_info

      # These are possible npm versioning tags that can be used in place of a version.
      # See https://docs.npmjs.com/cli/v10/commands/npm-dist-tag#purpose for more details.
      VERSION_TAGS = T.let([
        "alpha",        # Alpha version, early testing phase
        "beta",         # Beta version, more stable than alpha
        "canary",       # Canary version, often used for cutting-edge builds
        "dev",          # Development version, ongoing development
        "experimental", # Experimental version, unstable and new features
        "latest",       # Latest stable version, used by npm to identify the current version of a package
        "legacy",       # Legacy version, older version maintained for compatibility
        "next",         # Next version, used by some projects to identify the upcoming version
        "nightly",      # Nightly build, daily builds often including latest changes
        "rc",           # Release candidate, potential final version
        "release",      # General release version
        "stable"        # Stable version, thoroughly tested and stable
      ].freeze.map(&:freeze), T::Array[String])

      VERSION_PATTERN = T.let(Gem::Version::VERSION_PATTERN + '(\+[0-9a-zA-Z\-.]+)?', String)
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        version = version.gsub(/^v/, "") if version.is_a?(String)

        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      sig { params(version: VersionParameter).returns(VersionParameter) }
      def self.semver_for(version)
        # The next two lines are to guard against improperly formatted
        # versions in a lockfile, such as an empty string or additional
        # characters. NPM/yarn fixes these when running an update, so we can
        # safely ignore these versions.
        return if version == ""
        return unless correct?(version)

        version
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        version = version.gsub(/^v/, "") if version.is_a?(String)
        @build_info = T.let(nil, T.nilable(String))

        version, @build_info = version.to_s.split("+") if version.to_s.include?("+")

        super(T.must(version))
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::NpmAndYarn::Version) }
      def self.new(version)
        T.cast(super, Dependabot::NpmAndYarn::Version)
      end

      sig { returns(Integer) }
      def major
        @major ||= T.let(segments[0].to_i, T.nilable(Integer))
      end

      sig { returns(Integer) }
      def minor
        @minor ||= T.let(segments[1].to_i, T.nilable(Integer))
      end

      sig { returns(Integer) }
      def patch
        @patch ||= T.let(segments[2].to_i, T.nilable(Integer))
      end

      sig { params(other: Dependabot::NpmAndYarn::Version).returns(T::Boolean) }
      def backwards_compatible_with?(other)
        case major
        when 0
          self == other
        else
          major == other.major && minor >= other.minor
        end
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

Dependabot::Utils
  .register_version_class("npm_and_yarn", Dependabot::NpmAndYarn::Version)
