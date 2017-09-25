# frozen_string_literal: true
require "excon"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module Python
      class Pip < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          potential_source_urls = [
            pypi_listing.dig("info", "home_page"),
            pypi_listing.dig("info", "bugtrack_url"),
            pypi_listing.dig("info", "download_url"),
            pypi_listing.dig("info", "docs_url")
          ].compact

          source_url = potential_source_urls.find { |url| url =~ SOURCE_REGEX }

          return nil unless source_url
          source_url.match(SOURCE_REGEX).named_captures
        end

        def pypi_listing
          @pypi_listing ||=
            begin
              url = "https://pypi.python.org/pypi/#{dependency.name}/json"
              middleware = SharedHelpers.excon_middleware

              JSON.parse(Excon.get(url, middlewares: middleware).body)
            end
        end
      end
    end
  end
end
