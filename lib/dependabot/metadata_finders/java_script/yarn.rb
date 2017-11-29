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
          return [] if npm_listing["versions"].nil?

          npm_listing["versions"].
            sort_by { |version, _| Gem::Version.new(version) }.
            reverse
        end

        def npm_listing
          return @npm_listing unless @npm_listing.nil?

          registry_auth_headers =
            if auth_token
              { "Authorization" => "Bearer #{auth_token}" }
            else
              {}
            end

          # NPM registries expect slashes to be escaped
          escaped_dependency_name = dependency.name.gsub("/", "%2f")

          response = Excon.get(
            "https://#{dependency_registry}/#{escaped_dependency_name}",
            headers: registry_auth_headers,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          begin
            @npm_listing = JSON.parse(response.body)
          rescue JSON::ParserError
            raise unless private_dependency_not_reachable?(response)
            @npm_listing = {}
          end
        end

        def dependency_registry
          source =
            dependency.requirements.map { |r| r.fetch(:source) }.compact.first

          if source.nil? then "registry.npmjs.org"
          else source.fetch(:url).gsub("https://", "")
          end
        end

        def auth_token
          credentials.
            find { |cred| cred["registry"] == dependency_registry }&.
            fetch("token")
        end

        def private_dependency_not_reachable?(npm_response)
          # Check whether this dependency is (likely to be) private
          if dependency_registry == "registry.npmjs.org" &&
             !dependency.name.start_with?("@")
            return false
          end

          [401, 403, 404].include?(npm_response.status)
        end
      end
    end
  end
end
