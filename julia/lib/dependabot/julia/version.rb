# typed: strong
# frozen_string_literal: true

require "dependabot/version"

module Dependabot
  module Julia
    class Version < Dependabot::Version
      # Julia follows semantic versioning for most packages
      # See: https://docs.julialang.org/en/v1/stdlib/Pkg/#Version-specifier-format
      VERSION_PATTERN = T.let(/^v?(\d+(?:\.\d+)*)(?:[-+].*)?$/, Regexp)

      sig { override.params(version: T.nilable(T.any(String, Integer, Gem::Version))).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version_string = version.to_s
        VERSION_PATTERN.match?(version_string)
      end

      sig { override.params(version: T.nilable(T.any(String, Integer, Gem::Version))).void }
      def initialize(version)
        version_string = version.to_s.strip

        # Remove 'v' prefix if present (common in Julia)
        version_string = version_string.sub(/^v/, "") if version_string.match?(/^v\d/)

        @version_string = T.let(version_string, String)
        super(version_string)
      end

      sig do
        override
          .params(version: T.nilable(T.any(String, Integer, Gem::Version)))
          .returns(Dependabot::Julia::Version)
      end
      def self.new(version)
        T.cast(super, Dependabot::Julia::Version)
      end
    end
  end
end

Dependabot::Utils.register_version_class("julia", Dependabot::Julia::Version)
