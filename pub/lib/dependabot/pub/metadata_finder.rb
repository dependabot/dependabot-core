# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module Pub
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        repo = pub_listing.dig("latest", "pubspec", "repository")
        # The repository field did not always exist in pubspec.yaml, and some 
        # packages specify a git repository in the "homepage" field.
        repo ||= pub_listing.dig("latest", "pubspec", "homepage")
        return nil unless repo

        Source.from_url(repo)
      end

      def pub_listing
        return @pub_listing unless @pub_listing.nil?

        response = Excon.get(
          "https://pub.dev/api/packages/#{dependency.name}",
          idempotent: true,
          **SharedHelpers.excon_defaults
        )

        @pub_listing = JSON.parse(response.body)
      end
    end
  end
end

Dependabot::MetadataFinders.register("pub", Dependabot::Pub::MetadataFinder)
