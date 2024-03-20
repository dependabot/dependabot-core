# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Version < Gem::Version
    extend T::Sig
    extend T::Helpers

    abstract!

    VersionParameter = T.type_alias { T.nilable(T.any(String, Integer, Gem::Version)) }

    sig { override.overridable.params(version: VersionParameter).void }
    def initialize(version)
      @original_version = T.let(version.to_s, String)

      super
    end

    sig { override.overridable.params(version: VersionParameter).returns(Dependabot::Version) }
    def self.new(version)
      T.cast(super, Dependabot::Version)
    end

    # Opt-in to Rubygems 4 behavior
    sig { override.overridable.params(version: VersionParameter).returns(T::Boolean) }
    def self.correct?(version)
      return false if version.nil?

      version.to_s.match?(ANCHORED_VERSION_PATTERN)
    end

    sig { overridable.returns(String) }
    def to_semver
      @original_version
    end
  end
end
