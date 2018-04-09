# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/update_checkers/php/composer"
require "dependabot/utils/php/version"

module Dependabot
  module UpdateCheckers
    module Php
      class Composer
        class VersionResolver
          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/

          def initialize(credentials:, dependency:, dependency_files:,
                         requirements_to_unlock:)
            @credentials = credentials
            @dependency = dependency
            @dependency_files = dependency_files
            @requirements_to_unlock = requirements_to_unlock
          end

          def latest_resolvable_version
            @latest_resolvable_version ||= fetch_latest_resolvable_version
          end

          private

          attr_reader :credentials, :dependency, :dependency_files,
                      :requirements_to_unlock

          def fetch_latest_resolvable_version
            version = fetch_latest_resolvable_version_string
            return if version.nil?
            return unless Utils::Php::Version.correct?(version)
            Utils::Php::Version.new(version)
          end

          def fetch_latest_resolvable_version_string
            SharedHelpers.in_a_temporary_directory do
              File.write("composer.json", prepared_composer_json_content)
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
            retry_count ||= 0
            retry_count += 1
            retry if retry_count < 2 && error.message.include?("404 Not Found")
            retry if retry_count < 2 && error.message.include?("timed out")
            handle_composer_errors(error)
          end

          def prepared_composer_json_content
            content = composer_file.content

            # We need to replace `git` types with `vcs` so that auth works. We
            # also have to do this in the FileUpdater, and return the altered
            # composer.json to the user.
            content = content.gsub(/"type"\s*:\s*"git"/, '"type": "vcs"')

            return content if requirements_to_unlock == :none

            old_requirement = dependency.requirements.first&.fetch(:requirement)
            new_requirement =
              if dependency.version then ">= #{dependency.version}"
              elsif old_requirement&.match?(VERSION_REGEX)
                ">= #{old_requirement.match(VERSION_REGEX)}"
              else "*"
              end

            content.gsub(
              /"#{Regexp.escape(dependency.name)}":\s*".*"/,
              %("#{dependency.name}": "#{new_requirement}")
            )
          end

          # rubocop:disable Metrics/PerceivedComplexity
          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/CyclomaticComplexity
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
            elsif error.message.start_with?("Could not parse version")
              raise Dependabot::DependencyFileNotResolvable, error.message
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
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/CyclomaticComplexity

          def php_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/php/bin/run.php")
          end

          def composer_file
            @composer_file ||=
              dependency_files.find { |f| f.name == "composer.json" }
          end

          def lockfile
            @lockfile ||=
              dependency_files.find { |f| f.name == "composer.lock" }
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
end
