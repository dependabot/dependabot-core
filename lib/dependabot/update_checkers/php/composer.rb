# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

require "json"

module Dependabot
  module UpdateCheckers
    module Php
      class Composer < Dependabot::UpdateCheckers::Base
        require_relative "composer/requirements_updater"
        require_relative "composer/version"
        require_relative "composer/requirement"

        def latest_version
          # Fall back to latest_resolvable_version if no listings found
          return latest_resolvable_version if registry_versions.empty?

          versions =
            registry_versions.
            select { |version| version_class.correct?(version.gsub(/^v/, "")) }.
            map { |version| version_class.new(version.gsub(/^v/, "")) }

          versions.reject!(&:prerelease?) unless wants_prerelease?
          versions.sort.last
        end

        def latest_resolvable_version
          @latest_resolvable_version ||=
            fetch_latest_resolvable_version(unlock_requirement: true)
        end

        def latest_resolvable_version_with_no_unlock
          @latest_resolvable_version_with_no_unlock ||=
            fetch_latest_resolvable_version(unlock_requirement: false)
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s,
            library: library?
          ).updated_requirements
        end

        def version_class
          Composer::Version
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Composer (yet)
          false
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

        def fetch_latest_resolvable_version(unlock_requirement:)
          version = fetch_latest_resolvable_version_string(
            unlock_requirement: unlock_requirement
          )

          return if version.nil?
          return unless version_class.correct?(version)
          version_class.new(version)
        end

        def fetch_latest_resolvable_version_string(unlock_requirement:)
          SharedHelpers.in_a_temporary_directory do
            File.write(
              "composer.json",
              prepared_composer_json_content(unlock_requirement)
            )
            File.write("composer.lock", lockfile.content) if lockfile

            SharedHelpers.run_helper_subprocess(
              command: "php -d memory_limit=-1 #{php_helper_path}",
              function: "get_latest_resolvable_version",
              args: [
                Dir.pwd,
                dependency.name.downcase,
                github_access_token,
                registry_credentials
              ]
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => error
          @retry_count ||= 0
          @retry_count += 1
          retry if @retry_count < 2 && error.message.include?("404 Not Found")
          retry if @retry_count < 2 && error.message.include?("timed out")
          handle_composer_errors(error)
        end

        def prepared_composer_json_content(unlock_requirement)
          return composer_file.content unless unlock_requirement

          new_requirement =
            dependency.version.nil? ? "*" : ">= #{dependency.version}"

          composer_file.content.gsub(
            /"#{Regexp.escape(dependency.name)}":\s*".*"/,
            %("#{dependency.name}": "#{new_requirement}")
          )
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

        def php_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/php/bin/run.php")
        end

        def registry_versions
          return @registry_versions unless @registry_versions.nil?

          repositories =
            JSON.parse(composer_file.content).
            fetch("repositories", []).
            select { |r| r.is_a?(Hash) }

          @registry_versions = []

          urls = repositories.
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
            middlewares: SharedHelpers.excon_middleware
          )

          return [] unless response.status == 200

          listing = JSON.parse(response.body)
          return [] if listing.nil?
          return [] if listing.fetch("packages") == []
          return [] unless listing.dig("packages", dependency.name.downcase)
          listing.dig("packages", dependency.name.downcase).keys
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def handle_composer_errors(error)
          if error.message.start_with?("Failed to execute git clone")
            dependency_url =
              error.message.match(/--mirror '(?<url>.*?)'/).
              named_captures.fetch("url")
            raise Dependabot::GitDependenciesNotReachable, dependency_url
          elsif error.message.start_with?("Failed to clone")
            dependency_url =
              error.message.match(/Failed to clone (?<url>.*?) via/).
              named_captures.fetch("url")
            raise Dependabot::GitDependenciesNotReachable, dependency_url
          elsif error.message == "Requirements could not be resolved"
            # We should raise a Dependabot::DependencyFileNotResolvable error
            # here, but can't confidently distinguish between cases where we
            # can't install and cases where we can't update. For now, we
            # therefore just ignore the dependency.
            nil
          elsif error.message.include?("URL required authentication") ||
                error.message.include?("403 Forbidden")
            source =
              error.message.match(%r{https?://(?<source>[^/]+)/}).
              named_captures.fetch("source")
            raise Dependabot::PrivateSourceNotReachable, source
          elsif error.message.start_with?("Allowed memory size")
            raise "Composer out of memory"
          else
            raise error
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def library?
          JSON.parse(composer_file.content)["type"] == "library"
        end

        def github_access_token
          credentials.
            find { |cred| cred["host"] == "github.com" }.
            fetch("password")
        end

        def registry_credentials
          credentials.
            select { |cred| cred.key?("registry") }
        end
      end
    end
  end
end
