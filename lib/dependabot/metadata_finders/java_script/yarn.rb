# frozen_string_literal: true
require "excon"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module JavaScript
      class Yarn < Dependabot::MetadataFinders::Base
        private

        def look_up_github_repo
          version_listings =
            npm_listing["versions"].
            sort_by { |version, _| Gem::Version.new(version) }.
            reverse

          potential_source_urls =
            version_listings.flat_map do |_, listing|
              [
                get_url(listing["repository"]),
                listing["homepage"],
                get_url(listing["bugs"])
              ]
            end.compact

          source_url = potential_source_urls.find { |url| url =~ SOURCE_REGEX }

          return nil unless source_url
          return nil unless source_url.match(SOURCE_REGEX)[:host] == "github"
          source_url.match(SOURCE_REGEX)[:repo]
        end

        def get_url(details)
          case details
          when String then details
          when Hash then details.fetch("url", nil)
          end
        end

        def npm_listing
          return @npm_listing unless @npm_listing.nil?

          # NPM registry expects slashes to be escaped
          url = "https://registry.npmjs.org/#{dependency.name.gsub('/', '%2f')}"
          response = Excon.get(url, middlewares: SharedHelpers.excon_middleware)

          @npm_listing = JSON.parse(response.body)
        end
      end
    end
  end
end
