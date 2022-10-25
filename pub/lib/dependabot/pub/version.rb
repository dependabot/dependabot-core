# frozen_string_literal: true

require "dependabot/utils"
require "rubygems_version_patch"

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
    class Version < Gem::Version
      VERSION_PATTERN = Gem::Version::VERSION_PATTERN + "(\\+[0-9a-zA-Z\\-.]+)?"
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

      attr_reader :build_info

      def initialize(version)
        @version_string = version.to_s
        version, @build_info = version.to_s.split("+") if version.to_s.include?("+")

        super
      end

      def to_s
        @version_string
      end

      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end
    end
  end
end

Dependabot::Utils.register_version_class("pub", Dependabot::Pub::Version)
