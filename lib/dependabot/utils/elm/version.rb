# frozen_string_literal: true

# Elm versions require major, minor and patch to be present
# They don't allow any letters

module Dependabot
  module Utils
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
end
