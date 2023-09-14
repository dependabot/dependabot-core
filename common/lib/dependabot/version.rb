# typed: strong
# frozen_string_literal: true

module Dependabot
  class Version < Gem::Version
    extend T::Sig

    sig { override.params(version: String).void }
    def initialize(version)
      @original_version = version

      super
    end

    # Opt-in to Rubygems 4 behavior
    sig { override.params(version: Object).returns(T::Boolean) }
    def self.correct?(version)
      return false if version.nil?

      version.to_s.match?(ANCHORED_VERSION_PATTERN)
    end

    sig { returns(String) }
    def to_semver
      @original_version
    end
  end
end
