# frozen_string_literal: true

require "dependabot/utils"
require "rubygems_version_patch"

# JavaScript pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
#
# See https://semver.org/ for details of node's version syntax.

module Dependabot
  module NpmAndYarn
    class Version < Gem::Version
      attr_reader :build_info

      VERSION_PATTERN = Gem::Version::VERSION_PATTERN + '(\+[0-9a-zA-Z\-.]+)?'
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/.freeze

      def self.correct?(version)
        version = version.gsub(/^v/, "") if version.is_a?(String)

        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      def initialize(version)
        @version_string = version.to_s
        version = version.gsub(/^v/, "") if version.is_a?(String)

        if version.to_s.include?("+")
          version, @build_info = version.to_s.split("+")
        end

        super
      end

      def to_s
        @version_string
      end

      def inspect
        "#<#{self.class} #{@version_string}>"
      end
    end
  end
end

Dependabot::Utils.
  register_version_class("npm_and_yarn", Dependabot::NpmAndYarn::Version)
