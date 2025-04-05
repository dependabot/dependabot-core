# typed: true
# frozen_string_literal: true

require "excon"
require "json"

require "dependabot/composer/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Composer
    class UpdateChecker
      class LatestVersionFinder
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, raise_on_ignored: false,
                       security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
        end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def lowest_security_fix_version
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version
        end

        private

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :credentials
        attr_reader :ignored_versions
        attr_reader :security_advisories

        def fetch_latest_version
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions.max
        end

        def fetch_lowest_security_fix_version
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(versions,
                                                                                           security_advisories)
          versions = filter_ignored_versions(versions)
          versions = filter_lower_versions(versions)

          versions.min
        end

        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        def filter_ignored_versions(versions_array)
          filtered =
            versions_array
            .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }

          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise AllVersionsIgnored
          end

          filtered
        end

        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array
            .select { |version| version > dependency.numeric_version }
        end

        def wants_prerelease?
          current_version = dependency.numeric_version
          return true if current_version&.prerelease?

          dependency.requirements.any? do |req|
            req[:requirement].match?(/\d-[A-Za-z]/)
          end
        end

        def available_versions
          registry_version_details
            .select { |version| version_class.correct?(version.gsub(/^v/, "")) }
            .map { |version| version_class.new(version.gsub(/^v/, "")) }
        end

        def registry_version_details
          return @registry_version_details unless @registry_version_details.nil?

          repositories =
            JSON.parse(composer_file.content)
                .fetch("repositories", [])
                .select { |r| r.is_a?(Hash) }

          urls = repositories
                 .select { |h| h["type"] == PackageManager::NAME }
                 .filter_map { |h| h["url"] }
                 .map { |url| url.gsub(%r{\/$}, "") + "/packages.json" }

          unless repositories.any? { |rep| rep["packagist.org"] == false }
            urls << "https://repo.packagist.org/p2/#{dependency.name.downcase}.json"
          end

          @registry_version_details = []
          urls.each do |url|
            @registry_version_details += fetch_registry_versions_from_url(url)
          end
          @registry_version_details.uniq
        end

        def fetch_registry_versions_from_url(url)
          url_host = URI(url).host
          cred = registry_credentials.find { |c| url_host == c["registry"] || url_host == URI(c["registry"]).host }

          response = Dependabot::RegistryClient.get(
            url: url,
            options: {
              user: cred&.fetch("username", nil),
              password: cred&.fetch("password", nil)
            }
          )

          parse_registry_response(response, url)
        rescue Excon::Error::Socket, Excon::Error::Timeout
          []
        end

        def parse_registry_response(response, url)
          return [] unless response.status == 200

          listing = JSON.parse(response.body)
          return [] if listing.nil?
          return [] unless listing.is_a?(Hash)
          return [] if listing.fetch("packages", []) == []
          return [] unless listing.dig("packages", dependency.name.downcase)

          extract_versions(listing)
        rescue JSON::ParserError
          msg = "'#{url}' does not contain valid JSON"
          raise DependencyFileNotResolvable, msg
        end

        def extract_versions(listing)
          # Packagist's Metadata API format:
          # v1: "packages": {<package name>: {<version_number>: {hash of metadata for a particular release version}}}
          # v2: "packages": {<package name>: [{hash of metadata for a particular release version}]}
          version_listings = listing.dig("packages", dependency.name.downcase)

          if version_listings.is_a?(Hash) # some private registries are still using the v1 format
            # Regardless of API version, composer always reads the version from the metadata hash. So for the v1 API,
            # ignore the keys as repositories other than packagist.org could be using different keys. Instead, coerce
            # to an array of metadata hashes to match v2 format.
            version_listings = version_listings.values
          end

          if version_listings.is_a?(Array)
            version_listings.map { |i| i.fetch("version") }
          else
            []
          end
        end

        def registry_credentials
          credentials.select { |cred| cred["type"] == PackageManager::REPOSITORY_KEY } +
            auth_json_credentials
        end

        def auth_json_credentials
          return [] unless auth_json

          parsed_auth_json = JSON.parse(auth_json.content)
          parsed_auth_json.fetch("http-basic", {}).map do |reg, details|
            {
              "registry" => reg,
              "username" => details["username"],
              "password" => details["password"]
            }
          end
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, auth_json.path
        end

        def composer_file
          composer_file =
            dependency_files.find do |f|
              f.name == PackageManager::MANIFEST_FILENAME
            end
          raise "No #{PackageManager::MANIFEST_FILENAME}!" unless composer_file

          composer_file
        end

        def auth_json
          dependency_files.find { |f| f.name == PackageManager::AUTH_FILENAME }
        end

        def ignore_requirements
          ignored_versions.map { |req| requirement_class.new(req.split(",")) }
        end

        def version_class
          dependency.version_class
        end

        def requirement_class
          dependency.requirement_class
        end
      end
    end
  end
end
