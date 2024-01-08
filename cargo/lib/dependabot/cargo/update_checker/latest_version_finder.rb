# typed: true
# frozen_string_literal: true

require "excon"
require "dependabot/cargo/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"

module Dependabot
  module Cargo
    class UpdateChecker
      class LatestVersionFinder
        CRATES_IO_DL = "https://crates.io/api/v1/crates"

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, raise_on_ignored: false,
                       security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
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
          versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(versions,
                                                                                           security_advisories)
          versions = filter_ignored_versions(versions)
          versions = filter_lower_versions(versions)

          versions.min
        end

        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        def filter_ignored_versions(versions_array)
          filtered = versions_array
                     .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise Dependabot::AllVersionsIgnored
          end

          filtered
        end

        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array
            .select { |version| version > dependency.numeric_version }
        end

        def available_versions
          crates_listing
            .fetch("versions", [])
            .reject { |v| v["yanked"] }
            .map { |v| version_class.new(v.fetch("num")) }
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def crates_listing
          return @crates_listing unless @crates_listing.nil?

          info = dependency.requirements.filter_map { |r| r[:source] }.first
          dl = (info && info[:dl]) || CRATES_IO_DL

          # Default request headers
          hdrs = { "User-Agent" => "Dependabot (dependabot.com)" }

          if info && dl != CRATES_IO_DL
            # Add authentication headers if credentials are present for this registry
            registry_creds = credentials.find do |cred|
              cred["type"] == "cargo_registry" && cred["registry"] == info[:name]
            end

            hdrs["Authorization"] = "Token #{registry_creds['token']}"
          end

          url = if %w({crate} {version}).any? { |w| dl.include?(w) }
                  # TODO: private registries don't have a defined API pattern for metadata
                  # dl.gsub("{crate}", dependency.name).gsub("{version}", dependency.version)
                  return {}
                else
                  "#{dl}/#{dependency.name}"
                end

          response = Excon.get(
            url,
            headers: hdrs,
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          @crates_listing = JSON.parse(response.body)
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def wants_prerelease?
          return true if dependency.numeric_version&.prerelease?

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.match?(/[A-Za-z]/) }
          end
        end

        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
        end

        def version_class
          dependency.version_class
        end

        def requirement_class
          dependency.requirement_class
        end
      end
    end
  end
end
