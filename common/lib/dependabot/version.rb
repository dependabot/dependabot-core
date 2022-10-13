# frozen_string_literal: true

module Dependabot
  class Version < Gem::Version
    def initialize(version)
      @original_version = version

      super
    end

    # Opt-in to Rubygems 4 behavior
    def self.correct?(version)
      return false if version.nil?

      version.to_s.match?(ANCHORED_VERSION_PATTERN)
    end

    def to_semver
      @original_version
    end
  end
end
