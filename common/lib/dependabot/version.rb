# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Version < Gem::Version
    extend T::Sig
    extend T::Helpers

    abstract!

    sig do
      override
        .overridable
        .params(
          version: T.any(
            String,
            Integer,
            Float,
            Gem::Version,
            NilClass
          )
        )
        .void
    end
    def initialize(version)
      @original_version = T.let(version.to_s, String)

      T.unsafe(super(version))
    end

    sig do
      override
        .overridable
        .params(
          version: T.any(
            String,
            Integer,
            Float,
            Gem::Version,
            NilClass
          )
        )
        .returns(Dependabot::Version)
    end
    def self.new(version)
      T.cast(super, Dependabot::Version)
    end

    # Opt-in to Rubygems 4 behavior
    sig do
      override
        .overridable
        .params(
          version: T.any(
            String,
            Integer,
            Float,
            Gem::Version,
            NilClass
          )
        )
        .returns(T::Boolean)
    end
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
