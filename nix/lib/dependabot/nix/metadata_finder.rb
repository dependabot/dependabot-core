# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/nix/channel"

module Dependabot
  module Nix
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      # Channel tarballs resolve to nixpkgs revisions, so metadata points there.
      NIXPKGS_SOURCE_URL = "https://github.com/NixOS/nixpkgs"

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        url = source_string(dependency.requirements.first&.source, "url")

        return Source.from_url(NIXPKGS_SOURCE_URL) if Channel.channel_url?(url)

        Source.from_url(url)
      end

      sig do
        params(
          source: T.nilable(Dependabot::DependencyRequirement::Details),
          key: String
        ).returns(T.nilable(String))
      end
      def source_string(source, key)
        return unless source

        value = source[key] || source[key.to_sym]
        value if value.is_a?(String)
      end
    end
  end
end

Dependabot::MetadataFinders.register("nix", Dependabot::Nix::MetadataFinder)
