# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
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

        RELEASES_URL = "https://api.github.com/repos/"
        APPLICATION_JSON = "JSON"

        sig { params(dependency: Dependency, credentials: T::Array[Dependabot::Credential]).void }
        def initialize(dependency:, credentials:)
          super
          @dependency = dependency
          @credentials = credentials
        end

        sig { returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def fetch_version_and_release_date
          url = RELEASES_URL + "#{@dependency.name}/releases"
          # Fetch the releases from the GitHub API
          response = Excon.get(url, headers: { "Accept" => "application/vnd.github.v3+json" })

          # Raise an error if the request fails
          raise "Failed to fetch releases: #{response.status}" unless response.status == 200

          # Parse the JSON response
          releases = JSON.parse(response.body)

          # Extract version names and release dates into a hash
          package_releases = releases.map do |release|
            package_release(
              version: release["tag_name"],
              released_at: Time.parse(release["published_at"]),
              url: url
            )
          end

          # Log the extracted details for debugging
          Dependabot.logger.info("Extracted release details: #{package_releases}")

          package_details(package_releases)
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(Dependabot::Package::PackageDetails)
        end

        # This method creates a PackageDetails object from the releases hashand returns it.
        def package_details(releases)
          @package_details ||= T.let(
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: releases.uniq(&:version)
            ), T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig do
          params(
            version: String,
            released_at: Time,
            url: String,
            yanked: T::Boolean
          ).returns(Dependabot::Package::PackageRelease)
        end

        def package_release(version:, released_at:, url:, yanked: false)
          normalized_version = version.sub(/^v/, "") # Remove the "v" prefix if it exists
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Swift::Version.new(normalized_version),
            released_at: released_at,
            yanked: yanked,
            yanked_reason: nil,
            downloads: 0,
            url: url,
            package_type: "swift",
            language: Dependabot::Package::PackageLanguage.new(
              name: "swift",
              version: nil,
              requirement: nil
            )
          )
        end
      end
    end
  end
end
