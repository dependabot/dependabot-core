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
                         requirements_to_unlock:, latest_allowable_version:)
            @credentials              = credentials
            @dependency               = dependency
            @dependency_files         = dependency_files
            @requirements_to_unlock   = requirements_to_unlock
            @latest_allowable_version = latest_allowable_version
          end

          def latest_resolvable_version
            @latest_resolvable_version ||= fetch_latest_resolvable_version
          end

          private

          attr_reader :credentials, :dependency, :dependency_files,
                      :requirements_to_unlock, :latest_allowable_version

          def fetch_latest_resolvable_version
            version = fetch_latest_resolvable_version_string
            return if version.nil?
            return unless Utils::Php::Version.correct?(version)
            Utils::Php::Version.new(version)
          end

          def fetch_latest_resolvable_version_string
            base_directory = dependency_files.first.directory
            SharedHelpers.in_a_temporary_directory(base_directory) do
              File.write("composer.json", prepared_composer_json_content)
              File.write("composer.lock", lockfile.content) if lockfile

              SharedHelpers.run_helper_subprocess(
                command: "php -d memory_limit=-1 #{php_helper_path}",
                function: "get_latest_resolvable_version",
                args: [
                  Dir.pwd,
                  dependency.name.downcase,
                  git_credentials,
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
            content = content.gsub(%r{git@(.*?)[:/]}, 'https://\1/')
            content = content.gsub(/"no-api"\s*:\s*true,\n/, "")

            content.gsub(
              /"#{Regexp.escape(dependency.name)}"\s*:\s*".*"/,
              %("#{dependency.name}": "#{updated_version_requirement_string}")
            )
          end

          def updated_version_requirement_string
            lower_bound =
              if requirements_to_unlock == :none
                dependency.requirements.first&.fetch(:requirement) || ">= 0"
              elsif dependency.version
                ">= #{dependency.version}"
              else
                version_for_requirement =
                  dependency.requirements.map { |r| r[:requirement] }.compact.
                  reject { |req_string| req_string.start_with?("<") }.
                  select { |req_string| req_string.match?(VERSION_REGEX) }.
                  map { |req_string| req_string.match(VERSION_REGEX) }.
                  select { |version| Gem::Version.correct?(version) }.
                  max_by { |version| Gem::Version.new(version) }

                ">= #{version_for_requirement || 0}"
              end

            # Add the latest_allowable_version as an upper bound. This means
            # ignore conditions are considered when checking for the latest
            # resolvable version.
            #
            # NOTE: This isn't perfect. If v2.x is ignored and v3 is out but
            # unresolvable then the `latest_allowable_version` will be v3, and
            # we won't be ignoring v2.x releases like we should be.
            return lower_bound unless latest_allowable_version
            lower_bound + ", <= #{latest_allowable_version}"
          end

          # rubocop:disable Metrics/PerceivedComplexity
          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/MethodLength
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
            elsif error.message.include?("requested PHP extension")
              extensions = error.message.scan(/\sext\-.*?\s/).map(&:strip).uniq
              msg = "Dependabot's installed extensions didn't match those "\
                    "required by your application. Please add the following "\
                    "extensions to your platform config: "\
                    "#{extensions.join(', ')}.\n\n"\
                    "The full error raised was:\n\n#{error.message}"
              raise Dependabot::DependencyFileNotResolvable, msg
            elsif error.message.include?("package requires php")
              raise Dependabot::DependencyFileNotResolvable, error.message
            elsif error.message.include?("requirements could not be resolved")
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
              raise Dependabot::PrivateSourceAuthenticationFailure, source
            elsif error.message.start_with?("Allowed memory size")
              raise "Composer out of memory"
            else
              raise error
            end
          end
          # rubocop:enable Metrics/PerceivedComplexity
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/MethodLength

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

          def git_credentials
            credentials.select { |cred| cred["type"] == "git_source" }
          end

          def registry_credentials
            credentials.select { |cred| cred["type"] == "composer_repository" }
          end
        end
      end
    end
  end
end
