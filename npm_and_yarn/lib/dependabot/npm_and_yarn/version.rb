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
      def self.correct?(version)
        version = version.gsub(/^v/, "") if version.is_a?(String)
        super(version)
      end

      def initialize(version)
        @version_string = version.to_s
        version = version.gsub(/^v/, "") if version.is_a?(String)
        super
      end

      def to_s
        @version_string
      end
    end
  end
end

Dependabot::Utils.register_version_class("npm_and_yarn", Dependabot::NpmAndYarn::Version)
