# typed: true
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

      sig { override.returns(T.nilable(Source)) }
      def look_up_source
        source_from_dependency || look_up_source_from_packagist
      end

      sig { returns(T.nilable(Source)) }
      def source_from_dependency
        source_url =
          dependency.requirements
                    .filter_map { |r| r.fetch(:source) }
                    .first&.fetch(:url, nil)

        Source.from_url(source_url)
      end

      sig { returns(T.nilable(Source)) }
      def look_up_source_from_packagist
        listing = packagist_listing
        return nil if listing&.fetch("packages", nil) == []

        packages = listing&.dig("packages", dependency.name.downcase)
        return nil unless packages

        # Packagist returns an array of version listings sorted newest to oldest.
        # So iterate until we find the first URL that appears to be a source URL.
        #
        # NOTE: Each listing may not have all fields because they are minified to remove duplicate elements:
        # * https://github.com/composer/composer/blob/main/UPGRADE-2.0.md#for-composer-repository-implementors
        # * https://github.com/composer/metadata-minifier
        packages.each do |i|
          [i["homepage"], i.dig("source", "url")].each do |url|
            source_url = Source.from_url(url)
            return source_url unless source_url.nil?
          end
        end
        nil
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def packagist_listing
        return @packagist_listing unless @packagist_listing.nil?

        response = Dependabot::RegistryClient.get(url: "https://repo.packagist.org/p2/#{dependency.name.downcase}.json")

        return nil unless response.status == 200

        @packagist_listing = JSON.parse(response.body)
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("composer", Dependabot::Composer::MetadataFinder)
