# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/python/package/package_registry_finder"

# Stores metadata for a package, including all its available versions
module Dependabot
  module Composer
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        PACKAGE_TYPE = "composer"
        PACKAGE_LANGUAGE = "php"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          raise_on_ignored: false
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories

          @registry_urls = T.let(nil, T.nilable(T::Array[String]))
          @registry_version_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_releases
          available_version_details = registry_version_details
                                      .select do |version_details|
            version = version_details.fetch("version")
            version && version_class.correct?(version.gsub(/^v/, ""))
          end

          releases = available_version_details.map do |version_details|
            format_version_release(version_details)
          end
          releases
        end

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          available_version_details = registry_version_details
                                      .select do |version_details|
            version = version_details.fetch("version")
            version && version_class.correct?(version.gsub(/^v/, ""))
          end

          releases = available_version_details.map do |version_details|
            format_version_release(version_details)
          end
          Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: releases.reverse.uniq(&:version)
          )
        end

        sig do
          returns(T::Array[T::Hash[String, T.untyped]])
        end
        def registry_version_details
          return @registry_version_details unless @registry_version_details.nil?

          repositories =
            JSON.parse(T.must(composer_file.content))
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

          @registry_version_details.uniq! { |version_details| version_details["version"] }
          @registry_version_details
        end

        sig { params(url: String).returns(T::Array[T::Hash[String, T.untyped]]) }
        def fetch_registry_versions_from_url(url)
          url_host = URI(url).host
          cred = registry_credentials.find { |c| url_host == c["registry"] || url_host == URI(T.must(c["registry"])).host } # rubocop:disable Layout/LineLength

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

        sig { params(response: T.untyped, url: String).returns(T::Array[T::Hash[String, T.untyped]]) }
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

        sig { params(listing: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[String, T.untyped]]) }
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
            version_listings
          else
            []
          end
        end

        sig do
          params(
            release_data: T::Hash[String, T.untyped]
          )
            .returns(Dependabot::Package::PackageRelease)
        end
        def format_version_release(release_data)
          version = release_data["version"].gsub(/^v/, "")
          released_at = release_data["time"] ? Time.parse(release_data["time"]) : nil # this will return nil if the time key is missing, avoiding error # rubocop:disable Layout/LineLength
          url = release_data["dist"] ? release_data["dist"]["url"] : nil
          package_type = PACKAGE_TYPE

          package_release(
            version: version,
            released_at: released_at,
            url: url,
            package_type: package_type
          )
        end

        sig do
          params(
            version: String,
            released_at: T.nilable(Time),
            downloads: T.nilable(Integer),
            url: T.nilable(String),
            yanked: T::Boolean,
            package_type: T.nilable(String)
          ).returns(Dependabot::Package::PackageRelease)
        end
        def package_release(version:, released_at:, downloads: nil, url: nil, yanked: false, package_type: nil)
          Dependabot::Package::PackageRelease.new(
            version: Composer::Version.new(version),
            released_at: released_at,
            yanked: yanked,
            yanked_reason: nil,
            downloads: downloads,
            url: url,
            package_type: package_type,
            language: nil
          )
        end

        sig { returns(Dependabot::DependencyFile) }
        def composer_file
          composer_file =
            dependency_files.find do |f|
              f.name == PackageManager::MANIFEST_FILENAME
            end
          raise "No #{PackageManager::MANIFEST_FILENAME}!" unless composer_file

          composer_file
        end

        sig { returns(T::Array[Dependabot::Credential]) }
        def registry_credentials
          credentials.select { |cred| cred["type"] == PackageManager::REPOSITORY_KEY } +
            auth_json_credentials
        end

        sig { returns(T::Array[Dependabot::Credential]) }
        def auth_json_credentials
          json = auth_json
          return [] unless json

          parsed_auth_json = JSON.parse(T.must(json.content))
          parsed_auth_json.fetch("http-basic", {}).map do |reg, details|
            Dependabot::Credential.new({
              "registry" => reg,
              "username" => details["username"],
              "password" => details["password"]
            })
          end
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, json.path if json

          raise Dependabot::DependencyFileNotParseable, "Unknown path"
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def auth_json
          dependency_files.find { |f| f.name == PackageManager::AUTH_FILENAME }
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def ignore_requirements
          ignored_versions.map { |req| requirement_class.new(req.split(",")) }
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T.class_of(Dependabot::Requirement)) }
        def requirement_class
          dependency.requirement_class
        end
      end
    end
  end
end
