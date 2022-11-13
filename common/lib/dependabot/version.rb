# frozen_string_literal: true

module Dependabot
  class Version < Gem::Version
    # Opt-in to Rubygems 4 behavior
    def self.correct?(version)
      return false if version.nil?

      version.to_s.match?(ANCHORED_VERSION_PATTERN)
    end
  end
end
