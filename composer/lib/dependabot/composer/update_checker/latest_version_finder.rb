# frozen_string_literal: true

require "excon"
require "json"

require "dependabot/composer/update_checker"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Composer
    class UpdateChecker
      class LatestVersionFinder
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
        end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def lowest_security_fix_version
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions, :security_advisories

        def fetch_latest_version
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions.max
        end

        def fetch_lowest_security_fix_version
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions = filter_vulnerable_versions(versions)
          versions = filter_lower_versions(versions)
          versions.min
        end

        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        def filter_ignored_versions(versions_array)
          versions_array.
            reject { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }
        end

        def filter_vulnerable_versions(versions_array)
          versions_array.
            reject { |v| security_advisories.any? { |a| a.vulnerable?(v) } }
        end

        def filter_lower_versions(versions_array)
          versions_array.
            select { |version| version > version_class.new(dependency.version) }
        end

        def wants_prerelease?
          current_version = dependency.version
          if current_version && version_class.new(current_version).prerelease?
            return true
          end

          dependency.requirements.any? do |req|
            req[:requirement].match?(/\d-[A-Za-z]/)
          end
        end

        def available_versions
          registry_version_details.
            select { |version| version_class.correct?(version.gsub(/^v/, "")) }.
            map { |version| version_class.new(version.gsub(/^v/, "")) }
        end

        def registry_version_details
          return @registry_version_details unless @registry_version_details.nil?

          repositories =
            JSON.parse(composer_file.content).
            fetch("repositories", []).
            select { |r| r.is_a?(Hash) }

          urls = repositories.
                 select { |h| h["type"] == "composer" }.
                 map { |h| h["url"] }.compact.
                 map { |url| url.gsub(%r{\/$}, "") + "/packages.json" }

          unless repositories.any? { |rep| rep["packagist.org"] == false }
            urls << "https://packagist.org/p/#{dependency.name.downcase}.json"
          end

          @registry_version_details = []
          urls.each do |url|
            @registry_version_details += fetch_registry_versions_from_url(url)
          end
          @registry_version_details.uniq
        end

        def fetch_registry_versions_from_url(url)
          cred = registry_credentials.find { |c| url.include?(c["registry"]) }

          response = Excon.get(
            url,
            idempotent: true,
            user: cred&.fetch("username", nil),
            password: cred&.fetch("password", nil),
            **SharedHelpers.excon_defaults
          )

          parse_registry_response(response, url)
        rescue Excon::Error::Socket, Excon::Error::Timeout
          []
        end

        def parse_registry_response(response, url)
          return [] unless response.status == 200

          listing = JSON.parse(response.body)
          return [] if listing.nil?
          return [] if listing.fetch("packages", []) == []
          return [] unless listing.dig("packages", dependency.name.downcase)

          listing.dig("packages", dependency.name.downcase).keys
        rescue JSON::ParserError
          msg = "'#{url}' does not contain valid JSON"
          raise DependencyFileNotResolvable, msg
        end

        def registry_credentials
          credentials.select { |cred| cred["type"] == "composer_repository" }
        end

        def composer_file
          composer_file =
            dependency_files.find { |f| f.name == "composer.json" }
          raise "No composer.json!" unless composer_file

          composer_file
        end

        def ignore_reqs
          ignored_versions.map { |req| requirement_class.new(req.split(",")) }
        end

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
        end

        def requirement_class
          Utils.requirement_class_for_package_manager(
            dependency.package_manager
          )
        end
      end
    end
  end
end
