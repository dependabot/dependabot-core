# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module Python
      class Pip < Dependabot::MetadataFinders::Base
        def homepage_url
          pypi_listing.dig("info", "home_page") || super
        end

        private

        def look_up_source
          potential_source_urls = [
            pypi_listing.dig("info", "home_page"),
            pypi_listing.dig("info", "bugtrack_url"),
            pypi_listing.dig("info", "download_url"),
            pypi_listing.dig("info", "docs_url")
          ].compact

          source_url = potential_source_urls.find { |url| url =~ SOURCE_REGEX }
          source_url ||= source_from_description

          return nil unless source_url
          captures = source_url.match(SOURCE_REGEX).named_captures
          Source.new(host: captures.fetch("host"), repo: captures.fetch("repo"))
        end

        def source_from_description
          github_urls = []
          desc = pypi_listing.dig("info", "description")
          return unless desc

          desc.scan(SOURCE_REGEX) { github_urls << Regexp.last_match.to_s }

          github_urls.find do |url|
            repo = url.match(SOURCE_REGEX).named_captures["repo"]
            repo.end_with?(dependency.name)
          end
        end

        def pypi_listing
          return @pypi_listing unless @pypi_listing.nil?
          return @pypi_listing = {} if dependency.version.include?("+")

          response = Excon.get(
            "https://pypi.python.org/pypi/#{dependency.name}/json",
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          @pypi_listing = JSON.parse(response.body)
        end
      end
    end
  end
end
