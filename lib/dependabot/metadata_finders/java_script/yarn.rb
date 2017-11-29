# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module JavaScript
      class Yarn < Dependabot::MetadataFinders::Base
        def homepage_url
          listing = version_listings.find { |_, l| l["homepage"] }
          listing&.last&.fetch("homepage", nil) || super
        end

        private

        def look_up_source
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
          captures = source_url.match(SOURCE_REGEX).named_captures
          Source.new(host: captures.fetch("host"), repo: captures.fetch("repo"))
        end

        def get_url(details)
          case details
          when String then details
          when Hash then details.fetch("url", nil)
          end
        end

        def version_listings
          npm_listing["versions"].
            sort_by { |version, _| Gem::Version.new(version) }.
            reverse
        end

        def npm_listing
          return @npm_listing unless @npm_listing.nil?

          npm_headers =
            if npm_auth_token
              { "Authorization" => "Bearer #{npm_auth_token}" }
            else
              {}
            end

          # NPM registry expects slashes to be escaped
          response = Excon.get(
            "https://registry.npmjs.org/#{dependency.name.gsub('/', '%2f')}",
            headers: npm_headers,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          @npm_listing = JSON.parse(response.body)
        end

        def npm_auth_token
          credentials.
            find { |cred| cred["registry"] == "registry.npmjs.org" }&.
            fetch("token")
        end
      end
    end
  end
end
