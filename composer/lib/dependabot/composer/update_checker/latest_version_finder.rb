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
        sig do
          override.returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def package_details
          @package_details ||= T.let(
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: available_versions.reverse.uniq(&:version)
            ), T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:, ignored_versions:, security_advisories:,
                       raise_on_ignored: false)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
        end

        sig do
          override.params(language_version: T.nilable(T.any(String, Dependabot::Version)))
                  .returns(T.nilable(Dependabot::Version))
        end
        def latest_version(language_version: nil)
          @latest_version ||= fetch_latest_version(language_version: language_version)
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def lowest_security_fix_version(language_version: nil)
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version(language_version: language_version)
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(language_version: nil)
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions.max_by(&:version)&.version
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_lowest_security_fix_version(language_version: nil)
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(versions,
                                                                                           security_advisories)
          versions = filter_ignored_versions(versions)
          versions = filter_lower_versions(versions)
          versions.min_by(&:version)&.version
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          current_version = dependency.numeric_version
          return true if current_version&.prerelease?

          dependency.requirements.any? do |req|
            req[:requirement].match?(/\d-[A-Za-z]/)
          end
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
          ).fetch
        end

        sig { params(url: String).returns(T::Array[String]) }
        def fetch_registry_versions_from_url(url)
          []
        rescue Excon::Error::Socket, Excon::Error::Timeout
          []
        end
      end
    end
  end
end
