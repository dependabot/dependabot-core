# typed: strict
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

require "dependabot/composer/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Composer
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

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
        def initialize(dependency:, dependency_files:, credentials:, ignored_versions:, security_advisories:,
                       raise_on_ignored: false)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_version
          @latest_version ||= T.let(
            fetch_latest_version,
            T.nilable(Dependabot::Version)
          )
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def lowest_security_fix_version
          @lowest_security_fix_version ||= T.let(
            fetch_lowest_security_fix_version,
            T.nilable(Dependabot::Version)
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(T.nilable(Dependabot::Version)) }
        def fetch_latest_version
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions.max
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def fetch_lowest_security_fix_version
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(versions,
                                                                                           security_advisories)
          versions = filter_ignored_versions(versions)
          versions = filter_lower_versions(versions)

          versions.min
        end

        sig { params(versions_array: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        sig { params(versions_array: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_ignored_versions(versions_array)
          filtered =
            versions_array
            .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }

          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise AllVersionsIgnored
          end

          filtered
        end

        sig { params(versions_array: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array
            .select { |version| version > dependency.numeric_version }
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          current_version = dependency.numeric_version
          return true if current_version&.prerelease?

          dependency.requirements.any? do |req|
            req[:requirement].match?(/\d-[A-Za-z]/)
          end
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def available_versions
          registry_version_details
            .select { |version| version_class.correct?(version.gsub(/^v/, "")) }
            .map { |version| version_class.new(version.gsub(/^v/, "")) }
        end

        sig { returns(T::Array[String]) }
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

          @registry_version_details ||= T.let([], T.nilable(T::Array[String]))
          urls.each do |url|
            @registry_version_details += fetch_registry_versions_from_url(url)
          end
          @registry_version_details.uniq
        end

        sig { params(url: String).returns(T::Array[String]) }
        def fetch_registry_versions_from_url(url)
          url_host = URI(url).host
          cred = registry_credentials.find do |c|
            url_host == c["registry"] || url_host == URI(T.must(c["registry"])).host
          end

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

        sig { params(response: T.untyped, url: String).returns(T::Array[String]) }
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

        sig { params(listing: T::Hash[String, T.untyped]).returns(T::Array[String]) }
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

        sig { returns(Dependabot::DependencyFile) }
        def composer_file
          composer_file =
            dependency_files.find do |f|
              f.name == PackageManager::MANIFEST_FILENAME
            end
          raise "No #{PackageManager::MANIFEST_FILENAME}!" unless composer_file

          composer_file
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
