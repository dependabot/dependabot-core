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
          # Filter based on UPPER BOUND constraints only (<, <=, !=)
          # We want to find the latest version that doesn't exceed upper limits
          # Lower bounds (>, >=) should NOT restrict - we want newer versions above lower bounds
          # Pinning constraints (==, ~=, ^) are the target of updates and should be ignored
          return releases if dependency.requirements.empty?

          reqs = extract_upper_bound_requirements
          return releases if reqs.empty?

          releases.select { |release| reqs.all? { |req| req.satisfied_by?(release.version) } }
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def extract_upper_bound_requirements
          T.let(
            dependency.requirements.filter_map do |r|
              requirement_value = r.fetch(:requirement, nil)
              # Skip if nil or not a String
              next unless requirement_value.is_a?(String)

              # Type guard above ensures requirement_value is a String
              requirement_string = T.let(requirement_value, String)
              upper_bound_parts = extract_upper_bound_parts(requirement_string)
              next if upper_bound_parts.empty?

              # Join upper bound parts and create a single requirement
              upper_bound_requirement_string = upper_bound_parts.join(",")
              requirement_class.new(upper_bound_requirement_string)
            end.compact,
            T::Array[Dependabot::Requirement]
          )
        end

        sig { params(requirement_string: String).returns(T::Array[String]) }
        def extract_upper_bound_parts(requirement_string)
          # Only extract UPPER BOUND constraints: <, <=, !=
          # NOT lower bounds (>, >=) - we want to find newer versions above lower bounds
          T.let(
            requirement_string.split(",").map(&:strip).select do |part|
              # Match < or <= (but not <=>) or != followed by version
              part.match?(/^\s*(<(?!=)|<=|!=)\s*\d/)
            end,
            T::Array[String]
          )
        end
      end
    end
  end
end
