# frozen_string_literal: true

# Go pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
# Best docs are at https://github.com/Masterminds/semver

require "dependabot/utils"

module Dependabot
  module GoModules
    class Version < Gem::Version
      VERSION_PATTERN = '[0-9]+[0-9a-zA-Z]*(?>\.[0-9a-zA-Z]+)*' \
                        '(-[0-9A-Za-z-]+(\.[0-9a-zA-Z-]+)*)?' \
                        '(\+incompatible)?'
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

      def self.correct?(version)
        version = version.gsub(/^v/, "") if version.is_a?(String)
        version = version.to_s.split("+").first if version.to_s.include?("+")

        super(version)
      end

      def initialize(version)
        @version_string = version.to_s.gsub(/^v/, "")
        version = version.gsub(/^v/, "") if version.is_a?(String)
        version = version.to_s.split("+").first if version.to_s.include?("+")

        super
      end

      def inspect # :nodoc:
        "#<#{self.class} #{@version_string.inspect}>"
      end

      def to_s
        @version_string
      end
    end
  end
end

Dependabot::Utils.
  register_version_class("go_modules", Dependabot::GoModules::Version)
