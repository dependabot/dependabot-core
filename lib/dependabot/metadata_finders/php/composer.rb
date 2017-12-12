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

          return unless source_url&.match?(SOURCE_REGEX)
          captures = source_url.match(SOURCE_REGEX).named_captures
          Source.new(host: captures.fetch("host"), repo: captures.fetch("repo"))
        end

        def look_up_source_from_packagist
          unless packagist_listing&.dig("packages", dependency.name.downcase)
            return nil
          end

          version_listings =
            packagist_listing["packages"][dependency.name.downcase].
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
          captures = source_url.match(SOURCE_REGEX).named_captures
          Source.new(host: captures.fetch("host"), repo: captures.fetch("repo"))
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
