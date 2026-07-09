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

        # Strip build metadata suffix (e.g. "0.0.43+1" -> "0.0.43"). Julia's JLL
        # packages use the "+N" suffix to identify rebuilds of the same source
        # version; per semver build metadata is ignored when ordering versions,
        # and Julia's Pkg treats "0.0.43" and "0.0.43+1" as compatibility-equivalent.
        version_string = version_string.sub(/\+.*\z/, "")

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
