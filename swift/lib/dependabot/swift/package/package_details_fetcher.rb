# typed: true
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/swift"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/package/package_language"
module Dependabot
  module Swift
    module Package
      class PackageDetailsFetcher < Dependabot::MetadataFinders::Base
        extend T::Sig

        RELEASES_URL = "https://github.com/patrick-zippenfenig/SwiftNetCDF/tags"
        APPLICATION_HTML = "text/html; charset=utf-8"

        def initialize(dependency:, credentials:, repo_name: nil, package_manager: nil)
          @dependency_release_details_file = T.let(nil, T.nilable(Nokogiri::HTML::Document))
          @dependency = dependency
          @credentials = credentials
          @repo_name = repo_name
          @package_manager = package_manager
        end

        sig { returns(T.nilable(Nokogiri::HTML::Document)) }
        # This method fetches release details from GitHub using the Dependabot::RegistryClient.
        def fetch_release_details_from_github
          return @dependency_release_details_file unless @dependency_release_details_file.nil?

          return if RELEASES_URL.nil?

          response = Dependabot::RegistryClient.get(
            url: T.must(RELEASES_URL),
            headers: {
              "Accept" => APPLICATION_HTML
            }
          )

          @dependency_release_details_file = Nokogiri::HTML(response.body)
          Dependabot.logger.info("Fetched release details from GitHub: #{@dependency_release_details_file}")
          # Parse the response body as HTML
          html_doc = Nokogiri::HTML(response.body)

          # Extract release details (e.g., tags and dates)
          releases = html_doc.css("div.release-entry").map do |release_entry|
          {
            tag: release_entry.at_css("div.release-header a").text.strip,
            release_date: release_entry.at_css("relative-time")&.attribute("datetime")&.value
          }
          end

          # Log the extracted release details for debugging
          Dependabot.logger.info("Fetched release details: #{releases}")

          # Cache the parsed document
          @dependency_release_details_file = html_doc
          # Return the parsed HTML document
          return html_doc
        end

        # sig { params(html_doc: T.any(Nokogiri::HTML::Document, Nokogiri::XML::Document)).returns(T::Hash[String, String]) }
        # This method parses the HTML document and extracts release details
        # such as tags and release dates, returning them as a hash.
        def fetch_release_details(html_doc: Nokogiri::HTML::Document)
          # Parse the HTML document and extract release details
          release_details = html_doc.css("div.release-entry").each_with_object({}) do |release_entry, releases|
            tag = release_entry.at_css("div.release-header a")&.text&.strip
            release_date = release_entry.at_css("relative-time")&.attribute("datetime")&.value

            # Add to the hash table if both tag and release_date are present
            releases[tag] = release_date if tag && release_date
          end
          # Log the extracted release details for debugging
          Dependabot.logger.info("Parsed release details: #{release_details}")

          release_details
        end
      end
    end
  end
end
