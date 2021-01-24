# frozen_string_literal: true

# Go pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
# Best docs are at https://github.com/Masterminds/semver

require "dependabot/utils"

module Dependabot
  module Helm
    class Version < Gem::Version
      # Helm uses SemVer 2
      # https://helm.sh/docs/topics/charts/#charts-and-versioning
      # https://semver.org/
      PATTERN = %r{^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)
        (?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)
        (?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?
        (?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$}x

      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(PATTERN)
      end

      def initialize(version)
        @version_string = version.to_s

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

Dependabot::Utils.register_version_class("helm", Dependabot::Helm::Version)
