# typed: strong
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
          reqs = T.let(
            dependency.requirements.filter_map do |r|
              requirement_value = T.cast(r.fetch(:requirement), T.nilable(String))
              next if requirement_value.nil?

              requirement_string = requirement_value
              range_parts = T.let(
                requirement_string.split(",").map(&:strip).select do |part|
                  part.match?(/^\s*(<|>|>=|<=|!=)\s*\d/)
                end,
                T::Array[String]
              )

              range_parts.empty? ? nil : requirement_class.requirements_array(range_parts.join(","))
            end.flatten,
            T::Array[Dependabot::Requirement]
          )

          return releases if reqs.empty?

          releases.select do |release|
            reqs.all? { |req| req.satisfied_by?(release.version) }
          end
        end
      end
    end
  end
end
