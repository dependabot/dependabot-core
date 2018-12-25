# frozen_string_literal: true

require "rubygems_version_patch"

# Go pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
# Best docs are at https://github.com/Masterminds/semver

module Dependabot
  module Utils
    module Go
      class Version < Gem::Version
        VERSION_PATTERN = '[0-9]+[0-9a-zA-Z]*(?>\.[0-9a-zA-Z]+)*' \
                          '(-[0-9A-Za-z-]+(\.[0-9a-zA-Z-]+)*)?' \
                          '(\+incompatible)?'
        ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/.freeze

        def self.correct?(version)
          version = version.gsub(/^v/, "") if version.is_a?(String)
          version = version&.to_s&.split("+")&.first
          super(version)
        end

        def initialize(version)
          @version_string = version.to_s.gsub(/^v/, "")
          version = version.gsub(/^v/, "") if version.is_a?(String)
          version = version&.to_s&.split("+")&.first
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
end
