# typed: strict
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

require "dependabot/composer/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/composer/package/package_details_fetcher"
require "dependabot/package/package_latest_version_finder"

module Dependabot
  module Composer
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { returns(Package::PackageDetailsFetcher) }
        def fetcher
          Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories
          )
        end

        sig do
          override.returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def package_details
          @package_details ||= fetcher.fetch
        end

        protected

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          releases = available_versions
          releases = filter_prerelease_versions(releases)
          releases = filter_ignored_versions(releases)
          releases = filter_by_cooldown(releases)
          releases.max_by(&:version)&.version
        end

        private

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_lowest_security_fix_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          releases = available_versions
          releases = filter_prerelease_versions(releases)
          releases = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(releases,
                                                                                           security_advisories)
          releases = filter_ignored_versions(releases)
          releases = filter_lower_versions(releases)
          releases.min_by(&:version)&.version
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          current_version = dependency.numeric_version
          return true if current_version&.prerelease?

          dependency.requirements.any? do |req|
            req[:requirement].match?(/\d-[A-Za-z]/)
          end
        end

        sig { returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def available_versions
          Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            raise_on_ignored: false
          ).fetch_releases
        end

        sig { params(_url: String).returns(T::Array[String]) }
        def fetch_registry_versions_from_url(_url)
          []
        rescue Excon::Error::Socket, Excon::Error::Timeout
          []
        end
      end
    end
  end
end
