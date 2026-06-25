# typed: strict
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"
require "sorbet-runtime"

# Devbox package versions are nixpkgs versions. Alongside standard numeric
# versions ("3.10.19") and short prefixes ("3", "3.10"), Devbox supports a
# "latest" sentinel that always resolves to the newest release, so it must
# sort above any concrete version.

module Dependabot
  module Devbox
    class Version < Dependabot::Version
      extend T::Sig

      LATEST = "latest"

      # A value that sorts above any realistic nixpkgs version, used as the
      # internal representation of the "latest" sentinel since Gem::Version
      # cannot parse the word itself.
      LATEST_SENTINEL = T.let("999999", String)

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?
        return true if version.to_s.strip == LATEST

        super
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s.strip, String)
        @latest = T.let(@version_string == LATEST, T::Boolean)

        super(@latest ? LATEST_SENTINEL : version)
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Devbox::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Devbox::Version)
      end

      sig { returns(T::Boolean) }
      def latest?
        @latest
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { override.returns(String) }
      def inspect
        "#<#{self.class} #{@version_string}>"
      end
    end
  end
end

Dependabot::Utils.register_version_class("devbox", Dependabot::Devbox::Version)
