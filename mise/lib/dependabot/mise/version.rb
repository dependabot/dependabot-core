# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Mise
    class Version < Dependabot::Version
      extend T::Sig

      # Based on https://github.com/jdx/mise/blob/a4a1996f49779db556570678c81f658e5a28fe19/src/plugins/mod.rs#L334-L360
      PRERELEASE_PATTERN = /
        [.-](?:src|dev|latest|stm|rc|milestone|alpha|beta|pre|next|test|nightly|canary|experimental|insider|edge)|
        snapshot|master|
        \d[.-]?(?:alpha|beta|preview|pre|rc|a|b|c|dev)[.-]?\d*(?:\z|[^a-z0-9])
      /ix

      sig { override.params(version: T.nilable(T.any(String, Integer, ::Gem::Version))).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        super
      end

      sig { override.returns(T::Boolean) }
      def prerelease?
        @version_string.match?(PRERELEASE_PATTERN)
      end

      # A build suffix such as "-otp-29" or "-alpine3.18", as opposed to a prerelease marker such as "-rc.1".
      sig { params(version: String).returns(T::Boolean) }
      def self.build_suffix?(version)
        version.split("-").drop(1).any? do |part|
          # The numeric prefix lets the PEP 440 rule recognize markers such as "a1".
          part.match?(/[a-z]/i) && !PRERELEASE_PATTERN.match?("0-#{part}")
        end
      end

      # Preserve the original version string. Gem::Version may normalize version
      # segments internally, which would break round-trip fidelity when the file
      # updater writes the version back to mise.toml.
      sig { returns(String) }
      def to_s
        @version_string
      end

      sig { returns(String) }
      def inspect
        "#<Dependabot::Mise::Version #{@version_string.inspect}>"
      end
    end
  end
end

Dependabot::Utils.register_version_class("mise", Dependabot::Mise::Version)
