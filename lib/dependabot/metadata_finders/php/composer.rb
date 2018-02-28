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
          source_from_dependency || look_up_source_from_packagist
        end

        def source_from_dependency
          source_url =
            dependency.requirements.
            map { |r| r.fetch(:source) }.compact.
            first&.fetch(:url, nil)

          Source.from_url(source_url)
        end

        def look_up_source_from_packagist
          return nil if packagist_listing&.fetch("packages", nil) == []
          unless packagist_listing&.dig("packages", dependency.name.downcase)
            return nil
          end

          version_listings =
            packagist_listing["packages"][dependency.name.downcase].
            select { |version, _| Gem::Version.correct?(version) }.
            sort_by { |version, _| Gem::Version.new(version) }.
            map { |_, listing| listing }.
            reverse

          potential_source_urls =
            version_listings.
            flat_map { |info| [info["homepage"], info.dig("source", "url")] }.
            compact

          source_url = potential_source_urls.find { |url| Source.from_url(url) }

          Source.from_url(source_url)
        end

        def packagist_listing
          return @packagist_listing unless @packagist_listing.nil?

          response = Excon.get(
            "https://packagist.org/p/#{dependency.name.downcase}.json",
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          return nil unless response.status == 200

          @packagist_listing = JSON.parse(response.body)
        end
      end
    end
  end
end
