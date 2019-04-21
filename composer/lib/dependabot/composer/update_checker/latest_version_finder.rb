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
          return nil if path_dependency?

          @latest_version ||= fetch_latest_version_from_registry
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions, :security_advisories

        def fetch_latest_version_from_registry
          versions =
            registry_versions.
            select { |version| version_class.correct?(version.gsub(/^v/, "")) }.
            map { |version| version_class.new(version.gsub(/^v/, "")) }

          versions.reject!(&:prerelease?) unless wants_prerelease?
          versions.reject! { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }
          versions.max
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

        def path_dependency?
          dependency.requirements.any? { |r| r.dig(:source, :type) == "path" }
        end

        def registry_versions
          return @registry_versions unless @registry_versions.nil?

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

          @registry_versions = []
          urls.each do |url|
            @registry_versions += fetch_registry_versions_from_url(url)
          end
          @registry_versions.uniq
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
