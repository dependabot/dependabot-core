# frozen_string_literal: true

require "dependabot/utils"

# Rust pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.

module Dependabot
  module Cargo
    class Version < Gem::Version
      VERSION_PATTERN = '[0-9]+[0-9a-zA-Z]*(?>\.[0-9a-zA-Z]+)*' \
                        '(-[0-9A-Za-z-]+(\.[0-9a-zA-Z-]+)*)?' \
                        '(\+[0-9a-zA-Z]+(\.[0-9a-zA-Z]+)*)?'
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/.freeze

      def initialize(version)
        @version_string = version.to_s
        version, @build_version = version&.to_s&.split("+")
        super
      end

      def to_s
        @version_string
      end

      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end
    end
  end
end

Dependabot::Utils.register_version_class("cargo", Dependabot::Cargo::Version)
