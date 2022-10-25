# frozen_string_literal: true

require "dependabot/utils"
require "rubygems_version_patch"

# Elm versions require major, minor and patch to be present
# They don't allow any letters

module Dependabot
  module Elm
    class Version < Gem::Version
      VERSION_PATTERN = "[0-9]+\.[0-9]+\.[0-9]+"
      VERSION_PATTERN_REGEX = /\A#{VERSION_PATTERN}\Z/

      def self.correct?(version)
        version.to_s.match?(VERSION_PATTERN_REGEX)
      end
    end
  end
end

Dependabot::Utils.register_version_class("elm", Dependabot::Elm::Version)
