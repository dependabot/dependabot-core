# frozen_string_literal: true
require "excon"
require "bump/dependency_metadata_finders/base"
require "bump/shared_helpers"

module Bump
  module DependencyMetadataFinders
    class Python < Base
      private

      def look_up_github_repo
        potential_source_urls = [
          pypi_listing.dig("info", "home_page"),
          pypi_listing.dig("info", "bugtrack_url"),
          pypi_listing.dig("info", "download_url"),
          pypi_listing.dig("info", "docs_url")
        ].reject(&:nil?)

        source_url = potential_source_urls.find { |url| url =~ GITHUB_REGEX }

        source_url.match(GITHUB_REGEX)[:repo] if source_url
      end

      def pypi_listing
        return @pypi_listing unless @pypi_listing.nil?

        url = "https://pypi.python.org/pypi/#{dependency.name}/json"
        response = Excon.get(url, middlewares: SharedHelpers.excon_middleware)

        @pypi_listing = JSON.parse(response.body)
      end
    end
  end
end
