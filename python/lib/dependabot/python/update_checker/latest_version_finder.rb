# typed: strong
# frozen_string_literal: true

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

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T::Array[Dependabot::Version])
        end
        def eligible_versions(language_version: nil)
          releases = available_versions || []
          releases = filter_yanked_versions(releases)
          releases = filter_by_cooldown(releases)
          releases = filter_unsupported_versions(releases, language_version)
          releases = filter_prerelease_versions(releases)
          releases = filter_ignored_versions(releases)
          releases = apply_post_fetch_latest_versions_filter(releases)
          releases.map(&:version).uniq
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def resolver_excluded_versions
          releases = available_versions || []
          filtered_releases = filter_by_cooldown(filter_ignored_versions(releases))
          (releases.map(&:version) - filtered_releases.map(&:version)).uniq
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          return false if cooldown_options.nil?

          cooldown = T.must(cooldown_options)
          cooldown.default_days.to_i.positive? ||
            cooldown.semver_major_days.to_i.positive? ||
            cooldown.semver_minor_days.to_i.positive? ||
            cooldown.semver_patch_days.to_i.positive?
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(T::Array[Dependabot::Package::PackageRelease]))
        end
        def eligible_releases(language_version: nil)
          releases = available_versions
          return unless releases

          releases = filter_yanked_versions(releases)
          releases = filter_by_cooldown(releases)
          releases = filter_unsupported_versions(releases, language_version)
          releases = filter_prerelease_versions(releases)
          releases = filter_ignored_versions(releases)
          apply_post_fetch_latest_versions_filter(releases)
        end
      end
    end
  end
end
