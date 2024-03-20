# typed: true
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

# Dart pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
#
# For details on versions syntax supported by pub, see:
# https://semver.org/spec/v2.0.0-rc.1.html
#
# For details on semantics of version ranges as understood by pub, see:
# https://github.com/dart-lang/pub_semver

module Dependabot
  module Pub
    class Version < Dependabot::Version
      extend T::Sig

      VERSION_PATTERN = T.let(Gem::Version::VERSION_PATTERN + "(\\+[0-9a-zA-Z\\-.]+)?", String)
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

      sig { returns(String) }
      attr_reader :build_info

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        version, @build_info = version.to_s.split("+") if version.to_s.include?("+")

        super(T.must(version))
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Pub::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Pub::Version)
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { override.returns(String) }
      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end
    end
  end
end

Dependabot::Utils.register_version_class("pub", Dependabot::Pub::Version)
