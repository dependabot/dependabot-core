# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"
require "dependabot/composer/version"

module Dependabot
  module Composer
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        source_from_dependency || look_up_source_from_packagist
      end

      def source_from_dependency
        source_url =
          dependency.requirements.
          filter_map { |r| r.fetch(:source) }.
          first&.fetch(:url, nil)

        Source.from_url(source_url)
      end

      def look_up_source_from_packagist
        return nil if packagist_listing&.fetch("packages", nil) == []
        return nil unless packagist_listing&.dig("packages", dependency.name.downcase)

        version_listings = packagist_listing["packages"][dependency.name.downcase]
        # Packagist returns an array of version listings sorted newest to oldest.
        # So iterate until we find the first URL that appears to be a source URL.
        #
        # NOTE: Each listing may not have all fields because they are minified to remove duplicate elements:
        # * https://github.com/composer/composer/blob/main/UPGRADE-2.0.md#for-composer-repository-implementors
        # * https://github.com/composer/metadata-minifier
        version_listings.each do |i|
          [i["homepage"], i.dig("source", "url")].each do |url|
            source_url = Source.from_url(url)
            return source_url unless source_url.nil?
          end
        end
        nil
      end

      def packagist_listing
        return @packagist_listing unless @packagist_listing.nil?

        response = Dependabot::RegistryClient.get(url: "https://repo.packagist.org/p2/#{dependency.name.downcase}.json")

        return nil unless response.status == 200

        @packagist_listing = JSON.parse(response.body)
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("composer", Dependabot::Composer::MetadataFinder)
