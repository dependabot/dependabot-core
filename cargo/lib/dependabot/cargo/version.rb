# frozen_string_literal: true

require "dependabot/utils"
require "rubygems_version_patch"

# Rust pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.

module Dependabot
  module Cargo
    class Version < Gem::Version
      VERSION_PATTERN = '[0-9]+(?>\.[0-9a-zA-Z]+)*' \
                        '(-[0-9A-Za-z-]+(\.[0-9a-zA-Z-]+)*)?' \
                        '(\+[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)?'
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

      def initialize(version)
        @version_string = version.to_s
        version = version.to_s.split("+").first if version.to_s.include?("+")

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

Dependabot::Utils.register_version_class("cargo", Dependabot::Cargo::Version)
