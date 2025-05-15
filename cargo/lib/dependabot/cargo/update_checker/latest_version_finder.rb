# typed: true
# frozen_string_literal: true

require "excon"
require "dependabot/cargo/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "sorbet-runtime"

module Dependabot
  module Cargo
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

        CRATES_IO_API = "https://crates.io/api/v1/crates"

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

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :credentials
        attr_reader :ignored_versions
        attr_reader :security_advisories

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

        sig { params(versions_array: T::Array[Gem::Version]).returns(T::Array[Gem::Version]) }
        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          filtered = versions_array.reject(&:prerelease?)
          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} pre-release versions")
          end
          filtered
        end

        sig { params(versions_array: T::Array[Gem::Version]).returns(T::Array[Gem::Version]) }
        def filter_ignored_versions(versions_array)
          filtered = versions_array
                     .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise Dependabot::AllVersionsIgnored
          end

          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} ignored versions")
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
            # Handle both default and sparse registry responses.
            # Default registry uses "num" for version number.
            # Sparse registry uses "vers" for version number.
            .map do |v|
              version_number = v["num"] || v["vers"]
              version_class.new(version_number)
            end
        end

        def crates_listing
          return @crates_listing unless @crates_listing.nil?

          info = fetch_dependency_info
          index = fetch_index(info)

          hdrs = default_headers
          hdrs.merge!(auth_headers(info)) if index != CRATES_IO_API

          url = metadata_fetch_url(dependency, index)

          # B4PR
          puts "Calling #{url} to fetch metadata for #{dependency.name} from #{index}"

          response = fetch_response(url, hdrs)
          return {} if response.status == 404

          @crates_listing = parse_response(response, index)

          # B4PR
          puts "Fetched metadata for #{dependency.name} from #{index} successfully"
          puts response.body

          @crates_listing
        end

        def fetch_dependency_info
          dependency.requirements.filter_map { |r| r[:source] }.first
        end

        def fetch_index(info)
          (info && info[:index]) || CRATES_IO_API
        end

        def default_headers
          { "User-Agent" => "Dependabot (dependabot.com)" }
        end

        def auth_headers(info)
          registry_creds = credentials.find do |cred|
            cred["type"] == "cargo_registry" && cred["registry"] == info[:name]
          end

          return {} if registry_creds.nil?

          token = registry_creds["token"] || "placeholder_token"
          { "Authorization" => token }
        end

        def fetch_response(url, headers)
          Excon.get(
            url,
            idempotent: true,
            **SharedHelpers.excon_defaults(headers: headers)
          )
        end

        def parse_response(response, index)
          if index.start_with?("sparse+")
            parsed_response = response.body.lines.map { |line| JSON.parse(line) }
            { "versions" => parsed_response }
          else
            JSON.parse(response.body)
          end
        end

        def metadata_fetch_url(dependency, index)
          return "#{index}/#{dependency.name}" if index == CRATES_IO_API

          # Determine cargo's index file path for the dependency
          index = index.delete_prefix("sparse+")
          name_length = dependency.name.length
          dependency_path = case name_length
                            when 1, 2
                              "#{name_length}/#{dependency.name}"
                            when 3
                              "#{name_length}/#{dependency.name[0..1]}/#{dependency.name}"
                            else
                              "#{dependency.name[0..1]}/#{dependency.name[2..3]}/#{dependency.name}"
                            end

          "#{index}#{'/' unless index.end_with?('/')}#{dependency_path}"
        end

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
