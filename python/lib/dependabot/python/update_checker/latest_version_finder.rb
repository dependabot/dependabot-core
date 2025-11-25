# typed: strict
# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/python/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"
require "dependabot/python/package/package_registry_finder"
require "dependabot/python/package/package_details_fetcher"
require "dependabot/package/package_latest_version_finder"

module Dependabot
  module Python
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          override.returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def package_details
          @package_details ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          ).fetch
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        private

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_latest_versions_filter(releases)
          # Filter based on range requirements only (e.g., <, >, >=, <=, !=)
          # This allows finding the latest version while respecting upper/lower bounds
          # but ignoring pinning constraints like ==, ~=, ^ which are the target of the update
          return releases if dependency.requirements.empty?

          reqs = extract_range_requirements
          return releases if reqs.empty?

          releases.select { |release| reqs.all? { |req| req.satisfied_by?(release.version) } }
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def extract_range_requirements
          T.let(
            dependency.requirements.filter_map do |r|
              requirement_value = r.fetch(:requirement, nil)
              # Skip if nil or not a String
              next unless requirement_value.is_a?(String)

              # Type guard above ensures requirement_value is a String
              requirement_string = T.let(requirement_value, String)
              range_parts = extract_range_parts(requirement_string)
              next if range_parts.empty?

              # Join range parts and create a single requirement that handles comma-separated constraints
              range_requirement_string = range_parts.join(",")
              requirement_class.new(range_requirement_string)
            end.compact,
            T::Array[Dependabot::Requirement]
          )
        end

        sig { params(requirement_string: String).returns(T::Array[String]) }
        def extract_range_parts(requirement_string)
          T.let(
            requirement_string.split(",").map(&:strip).select do |part|
              part.match?(/^\s*(<|>|>=|<=|!=)\s*/)
            end,
            T::Array[String]
          )
        end
      end
    end
  end
end
