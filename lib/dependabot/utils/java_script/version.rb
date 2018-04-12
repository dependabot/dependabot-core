# frozen_string_literal: true

# JavaScript pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
#
# See https://semver.org/ for details of node's version syntax.

module Dependabot
  module Utils
    module JavaScript
      class Version < Gem::Version
        def self.correct?(version)
          super(version.gsub(/^v/, ""))
        end

        def initialize(version)
          @version_string = version.to_s
          version = version.gsub(/^v/, "")
          super
        end

        def to_s
          @version_string
        end
      end
    end
  end
end
