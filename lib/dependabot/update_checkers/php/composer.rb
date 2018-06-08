# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/utils/php/requirement"
require "dependabot/errors"

require "json"

module Dependabot
  module UpdateCheckers
    module Php
      class Composer < Dependabot::UpdateCheckers::Base
        require_relative "composer/requirements_updater"
        require_relative "composer/version_resolver"

        def latest_version
          return nil if path_dependency?

          # Fall back to latest_resolvable_version if no listings found
          latest_version_from_registry || latest_resolvable_version
        end

        def latest_resolvable_version
          return nil if path_dependency?

          @latest_resolvable_version ||=
            VersionResolver.new(
              credentials: credentials,
              dependency: dependency,
              dependency_files: dependency_files,
              latest_allowable_version: latest_version_from_registry,
              requirements_to_unlock: :own
            ).latest_resolvable_version
        end

        def latest_resolvable_version_with_no_unlock
          return nil if path_dependency?

          @latest_resolvable_version_with_no_unlock ||=
            VersionResolver.new(
              credentials: credentials,
              dependency: dependency,
              dependency_files: dependency_files,
              latest_allowable_version: latest_version_from_registry,
              requirements_to_unlock: :none
            ).latest_resolvable_version
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s,
            library: library?
          ).updated_requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Composer (yet)
          false
        end

        def latest_version_from_registry
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

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def path_dependency?
          dependency.requirements.any? { |r| r.dig(:source, :type) == "path" }
        end

        def composer_file
          composer_file =
            dependency_files.find { |f| f.name == "composer.json" }
          raise "No composer.json!" unless composer_file
          composer_file
        end

        def lockfile
          dependency_files.find { |f| f.name == "composer.lock" }
        end

        def registry_versions
          return @registry_versions unless @registry_versions.nil?

          repositories =
            JSON.parse(composer_file.content).
            fetch("repositories", []).
            select { |r| r.is_a?(Hash) }

          @registry_versions = []

          urls = repositories.
                 select { |h| h["type"] == "composer" }.
                 map { |h| h["url"] }.compact.
                 map { |url| url.gsub(%r{\/$}, "") + "/packages.json" }

          unless repositories.any? { |rep| rep["packagist.org"] == false }
            urls << "https://packagist.org/p/#{dependency.name.downcase}.json"
          end

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

          return [] unless response.status == 200

          listing = JSON.parse(response.body)
          return [] if listing.nil?
          return [] if listing.fetch("packages", []) == []
          return [] unless listing.dig("packages", dependency.name.downcase)
          listing.dig("packages", dependency.name.downcase).keys
        rescue Excon::Error::Socket, Excon::Error::Timeout
          []
        end

        def ignore_reqs
          ignored_versions.
            map { |req| Utils::Php::Requirement.new(req.split(",")) }
        end

        def library?
          JSON.parse(composer_file.content)["type"] == "library"
        end

        def registry_credentials
          credentials.select { |cred| cred["type"] == "composer_repository" }
        end
      end
    end
  end
end
