# frozen_string_literal: true

# Go pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
# Best docs are at https://github.com/Masterminds/semver

module Dependabot
  module Utils
    module Go
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
end
