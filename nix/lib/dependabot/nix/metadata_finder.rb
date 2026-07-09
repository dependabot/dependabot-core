# typed: strict
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
        source = dependency.requirements.first&.fetch(:source, nil)
        url = source && (source[:url] || source["url"])

        return Source.from_url(NIXPKGS_SOURCE_URL) if Channel.channel_url?(url)

        Source.from_url(url)
      end
    end
  end
end

Dependabot::MetadataFinders.register("nix", Dependabot::Nix::MetadataFinder)
