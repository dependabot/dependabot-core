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

        protected

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_latest_versions_filter(releases)
          # Filter out placeholder versions (0.0.0, 0.0, 0) which are commonly used
          # as development placeholders and should not be considered valid releases
          filtered = releases.reject do |release|
            version = T.cast(release.version, Dependabot::Python::Version)
            version.placeholder?
          end

          if releases.size > filtered.size
            Dependabot.logger.info("Filtered out #{releases.size - filtered.size} placeholder versions")
          end

          filtered
        end
      end
    end
  end
end
