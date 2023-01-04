# frozen_string_literal: true

require "excon"

require "dependabot/go_modules/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/go_modules/requirement"
require "dependabot/go_modules/resolvability_errors"

module Dependabot
  module GoModules
    class UpdateChecker
      class LatestVersionFinder
        RESOLVABILITY_ERROR_REGEXES = [
          # Package url/proxy doesn't include any redirect meta tags
          /no go-import meta tags/,
          # Package url 404s
          /404 Not Found/,
          /Repository not found/,
          /unrecognized import path/,
          /malformed module path/,
          # (Private) module could not be fetched
          /module .*: git ls-remote .*: exit status 128/m
        ].freeze
        INVALID_VERSION_REGEX = /version "[^"]+" invalid/m
        PSEUDO_VERSION_REGEX = /\b\d{14}-[0-9a-f]{12}$/

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, security_advisories:, raise_on_ignored: false,
                       goprivate:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
          @raise_on_ignored    = raise_on_ignored
          @goprivate           = goprivate
        end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def lowest_security_fix_version
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version
        end

        private

        attr_reader :dependency, :dependency_files, :credentials, :ignored_versions, :security_advisories

        def fetch_latest_version
          return dependency.version if PSEUDO_VERSION_REGEX.match?(dependency.version)

          candidate_versions = available_versions
          candidate_versions = filter_prerelease_versions(candidate_versions)
          candidate_versions = filter_ignored_versions(candidate_versions)

          candidate_versions.max
        end

        def fetch_lowest_security_fix_version
          return dependency.version if PSEUDO_VERSION_REGEX.match?(dependency.version)

          relevant_versions = available_versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(relevant_versions,
                                                                                                    security_advisories)
          relevant_versions = filter_ignored_versions(relevant_versions)
          relevant_versions = filter_lower_versions(relevant_versions)

          relevant_versions.min
        end

        def available_versions
          @available_versions ||= fetch_available_versions
        end

        def fetch_available_versions
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              manifest = parse_manifest

              # Set up an empty go.mod so 'go list -m' won't attempt to download dependencies. This
              # appears to be a side effect of operating with modules included in GOPRIVATE. We'll
              # retain any exclude directives to omit those versions.
              File.write("go.mod", "module dummy\n")
              manifest["Exclude"]&.each do |r|
                SharedHelpers.run_shell_command("go mod edit -exclude=#{r['Path']}@#{r['Version']}")
              end

              # Turn off the module proxy for private dependencies
              env = { "GOPRIVATE" => @goprivate }

              versions_json = SharedHelpers.run_shell_command(
                "go list -m -versions -json #{dependency.name}",
                fingerprint: "go list -m -versions -json <dependency_name>",
                env: env
              )
              version_strings = JSON.parse(versions_json)["Versions"]

              return [version_class.new(dependency.version)] if version_strings.nil?

              version_strings.select { |v| version_class.correct?(v) }.
                map { |v| version_class.new(v) }
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry_count ||= 0
          retry_count += 1
          retry if transitory_failure?(e) && retry_count < 2

          handle_subprocess_error(e)
        end

        def handle_subprocess_error(error)
          if RESOLVABILITY_ERROR_REGEXES.any? { |rgx| error.message =~ rgx }
            ResolvabilityErrors.handle(error.message, credentials: credentials, goprivate: @goprivate)
          elsif INVALID_VERSION_REGEX.match?(error.message)
            raise Dependabot::DependencyFileNotResolvable, error.message
          end

          raise
        end

        def transitory_failure?(error)
          return true if error.message.include?("EOF")

          error.message.include?("Internal Server Error")
        end

        def go_mod
          @go_mod ||= dependency_files.find { |f| f.name == "go.mod" }
        end

        def parse_manifest
          SharedHelpers.in_a_temporary_directory do
            File.write("go.mod", go_mod.content)
            json = SharedHelpers.run_shell_command("go mod edit -json")

            JSON.parse(json) || {}
          end
        end

        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array.
            select { |version| version > dependency.numeric_version }
        end

        def filter_ignored_versions(versions_array)
          filtered = versions_array.
                     reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise AllVersionsIgnored
          end

          filtered
        end

        def wants_prerelease?
          @wants_prerelease ||=
            begin
              current_version = dependency.numeric_version
              current_version&.prerelease?
            end
        end

        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
        end

        def requirement_class
          Utils.requirement_class_for_package_manager(
            dependency.package_manager
          )
        end

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
        end
      end
    end
  end
end
