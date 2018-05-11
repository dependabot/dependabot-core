# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module Python
      class Pip < Dependabot::MetadataFinders::Base
        MAIN_PYPI_URL = "https://pypi.org/pypi"

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

          source_url = potential_source_urls.find { |url| Source.from_url(url) }
          source_url ||= source_from_description
          source_url ||= source_from_homepage

          Source.from_url(source_url)
        end

        def source_from_description
          github_urls = []
          desc = pypi_listing.dig("info", "description")
          return unless desc

          desc.scan(Source::SOURCE_REGEX) do
            github_urls << Regexp.last_match.to_s
          end

          github_urls.find do |url|
            repo = Source.from_url(url).repo
            repo.downcase.end_with?(dependency.name)
          end
        end

        def source_from_homepage
          return unless homepage_body

          github_urls = []
          homepage_body.scan(Source::SOURCE_REGEX) do
            github_urls << Regexp.last_match.to_s
          end

          github_urls.find do |url|
            repo = Source.from_url(url).repo
            repo.downcase.end_with?(dependency.name)
          end
        end

        def homepage_body
          homepage_url = pypi_listing.dig("info", "home_page")

          return unless homepage_url
          return if homepage_url.include?("pypi.python.org")
          return if homepage_url.include?("pypi.org")

          @homepage_response ||=
            begin
              Excon.get(
                homepage_url,
                idempotent: true,
                omit_default_port: true,
                middlewares: SharedHelpers.excon_middleware
              )
            rescue Excon::Error::Timeout, Excon::Error::Socket, ArgumentError
              nil
            end

          return unless @homepage_response&.status == 200
          @homepage_response.body
        end

        def pypi_listing
          return @pypi_listing unless @pypi_listing.nil?
          return @pypi_listing = {} if dependency.version.include?("+")

          possible_listing_urls.each do |url|
            response = Excon.get(
              url,
              idempotent: true,
              omit_default_port: true,
              middlewares: SharedHelpers.excon_middleware
            )
            next unless response.status == 200

            @pypi_listing = JSON.parse(response.body)
            return @pypi_listing
          rescue JSON::ParserError
            next
          end

          @pypi_listing = {} # No listing found
        end

        def possible_listing_urls
          credential_urls =
            credentials.
            select { |cred| cred["index-url"] }.
            map { |cred| cred["index-url"].gsub(%r{/$}, "") }

          (credential_urls + [MAIN_PYPI_URL]).map do |base_url|
            base_url + "/#{dependency.name}/json"
          end
        end
      end
    end
  end
end
