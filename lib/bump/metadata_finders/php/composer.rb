# frozen_string_literal: true
require "excon"
require "bump/metadata_finders/base"
require "bump/shared_helpers"

module Bump
  module MetadataFinders
    module Php
      class Composer < Bump::MetadataFinders::Base
        private

        def look_up_github_repo
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

          source_url = potential_source_urls.find { |url| url =~ GITHUB_REGEX }

          source_url.match(GITHUB_REGEX)[:repo] if source_url
        end

        def packagist_listing
          return @packagist_listing unless @packagist_listing.nil?

          url = "https://packagist.org/p/#{dependency.name}.json"
          response = Excon.get(url, middlewares: SharedHelpers.excon_middleware)

          @packagist_listing = JSON.parse(response.body)
        end
      end
    end
  end
end
