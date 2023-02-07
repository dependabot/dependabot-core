# frozen_string_literal: true

require "rubygems/version"

# Opt in to Rubygems 4 behaviour
module Gem
  class Version
    def self.correct?(version)
      return false if version.nil?

      version.to_s.match?(ANCHORED_VERSION_PATTERN)
    end
  end
end

