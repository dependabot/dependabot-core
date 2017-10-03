# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module Php
      class Composer < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          version_listings =
            packagist_listing["packages"][dependency.name].
            sort_by do |version, _|
              begin
                Gem::Version.new(version)
              rescue ArgumentError
                Gem::Version.new(0)
              end
            end.
            reverse

          potential_source_urls =
            version_listings.flat_map do |_, listing|
              [listing["homepage"], listing.dig("source", "url")]
            end.compact

          source_url = potential_source_urls.find { |url| url =~ SOURCE_REGEX }

          return nil unless source_url
          source_url.match(SOURCE_REGEX).named_captures
        end

        def packagist_listing
          return @packagist_listing unless @packagist_listing.nil?

          response = Excon.get(
            "https://packagist.org/p/#{dependency.name}.json",
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          @packagist_listing = JSON.parse(response.body)
        end
      end
    end
  end
end
