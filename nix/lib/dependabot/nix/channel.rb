# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/nix/versioned_name"

module Dependabot
  module Nix
    # A NixOS channel: a VersionedName plus helpers for channel tarball URLs
    # (channels.nixos.org/<channel>/nixexprs.tar.xz).
    class Channel < VersionedName
      extend T::Sig

      CHANNEL_HOST = "channels.nixos.org"
      DEFAULT_EXTENSION = "xz"

      # e.g. https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz
      # The suffix is captured so a bump keeps the flake's existing format.
      CHANNEL_URL_PATTERN = %r{
        \Ahttps?://channels\.nixos\.org/
        (?<channel>[a-zA-Z0-9][a-zA-Z0-9._-]*)
        /nixexprs\.tar\.(?<extension>xz|gz|bz2)\z
      }x

      sig { params(url: T.nilable(String)).returns(T::Boolean) }
      def self.channel_url?(url)
        return false unless url

        CHANNEL_URL_PATTERN.match?(url)
      end

      sig { params(url: T.nilable(String)).returns(T.nilable(String)) }
      def self.channel_name_from_url(url)
        return unless url

        CHANNEL_URL_PATTERN.match(url)&.[](:channel)
      end

      # The compression suffix (xz, gz, bz2) of a channel tarball URL.
      sig { params(url: T.nilable(String)).returns(T.nilable(String)) }
      def self.extension_from_url(url)
        return unless url

        CHANNEL_URL_PATTERN.match(url)&.[](:extension)
      end

      # Preserves the flake's suffix so a bump keeps its compression format.
      sig { params(channel_name: String, extension: String).returns(String) }
      def self.url_for(channel_name, extension: DEFAULT_EXTENSION)
        "https://#{CHANNEL_HOST}/#{channel_name}/nixexprs.tar.#{extension}"
      end
    end
  end
end
