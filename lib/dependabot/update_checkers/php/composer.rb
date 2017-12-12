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

        def latest_version
          # Fall back to latest_resolvable_version if no listing on main
          # registry.
          # TODO: Check against all repositories, if alternatives are specified
          return latest_resolvable_version unless packagist_listing

          versions =
            packagist_listing["packages"][dependency.name.downcase].
            keys.map do |version|
              begin
                Gem::Version.new(version)
              rescue ArgumentError
                nil
              end
            end.compact

          versions.reject(&:prerelease?).sort.last
        end

        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s,
            existing_version: dependency.version&.to_s
          ).updated_requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Composer (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def fetch_latest_resolvable_version
          latest_resolvable_version =
            SharedHelpers.in_a_temporary_directory do
              File.write("composer.json", prepared_composer_json_content)
              File.write("composer.lock", lockfile.content)

              SharedHelpers.run_helper_subprocess(
                command: "php -d memory_limit=-1 #{php_helper_path}",
                function: "get_latest_resolvable_version",
                args: [Dir.pwd, dependency.name, github_access_token]
              )
            end

          if latest_resolvable_version.nil?
            nil
          else
            Gem::Version.new(latest_resolvable_version)
          end
        rescue SharedHelpers::HelperSubprocessFailed => error
          handle_composer_errors(error)
        end

        def prepared_composer_json_content
          composer_file.content.gsub(
            /"#{Regexp.escape(dependency.name)}":\s*".*"/,
            %("#{dependency.name}": "*")
          )
        end

        def composer_file
          composer_file =
            dependency_files.find { |f| f.name == "composer.json" }
          raise "No composer.json!" unless composer_file
          composer_file
        end

        def lockfile
          lockfile = dependency_files.find { |f| f.name == "composer.lock" }
          raise "No composer.lock!" unless lockfile
          lockfile
        end

        def php_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/php/bin/run.php")
        end

        def packagist_listing
          return @packagist_listing unless @packagist_listing.nil?

          response = Excon.get(
            "https://packagist.org/p/#{dependency.name.downcase}.json",
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          return nil unless response.status == 200

          @packagist_listing = JSON.parse(response.body)
        end

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
          else
            raise error
          end
        end

        def github_access_token
          credentials.
            find { |cred| cred["host"] == "github.com" }.
            fetch("password")
        end
      end
    end
  end
end
