# typed: strong
# frozen_string_literal: true

require "dependabot/package/package_latest_version_finder"
require "dependabot/package/release_cooldown_options"
require "dependabot/update_checkers/version_filters"
require "dependabot/maven/package/package_details_fetcher"
require "dependabot/maven/update_checker"
require "dependabot/maven/shared/shared_version_finder"
require "sorbet-runtime"

module Dependabot
  module Maven
    class UpdateChecker
      class VersionFinder < Dependabot::Maven::Shared::SharedVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          cooldown_options: nil,
          raise_on_ignored: false
        )
          @forbidden_urls      = T.let([], T::Array[String])
          @dependency_metadata = T.let({}, T::Hash[T.untyped, Nokogiri::XML::Document])
          @auth_headers_finder = T.let(nil, T.nilable(Utils::AuthHeadersFinder))
          @pom_repository_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @repository_finder = T.let(nil, T.nilable(Maven::FileParser::RepositoriesFinder))
          @repositories = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @released_check = T.let({}, T::Hash[Version, T::Boolean])
          @package_details_fetcher = T.let(nil, T.nilable(Package::PackageDetailsFetcher))
          @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
          super
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= package_details_fetcher.fetch
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def releases
          (package_details&.releases || []).reverse
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def latest_version_details
          release = fetch_latest_release
          release&.version ? { version: release.version, source_url: release.url } : nil
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def lowest_security_fix_version_details
          release = fetch_lowest_security_fix_release
          release&.version ? { version: release.version, source_url: release.url } : nil
        end

        protected

        sig { returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(language_version: nil)
          fetch_latest_release(language_version: language_version)&.version
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version_with_no_unlock(language_version:)
          fetch_latest_release(language_version: language_version)&.version
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_lowest_security_fix_version(language_version: nil)
          fetch_lowest_security_fix_release(language_version: language_version)&.version
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Package::PackageRelease))
        end
        def fetch_latest_release(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          possible_releases = filter_prerelease_versions(releases)
          possible_releases = filter_date_based_versions(possible_releases)
          possible_releases = filter_version_types(possible_releases)
          possible_releases = filter_ignored_versions(possible_releases)
          possible_releases = filter_by_cooldown(possible_releases)
          possible_releases_reverse = possible_releases.reverse

          possible_releases_reverse.find do |r|
            package_details_fetcher.released?(r.version)
          end
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Package::PackageRelease))
        end
        def fetch_lowest_security_fix_release(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          possible_releases = filter_prerelease_versions(releases)
          possible_releases = filter_date_based_versions(possible_releases)
          possible_releases = filter_version_types(possible_releases)
          possible_releases = Dependabot::UpdateCheckers::VersionFilters
                              .filter_vulnerable_versions(
                                possible_releases,
                                security_advisories
                              )
          possible_releases = filter_ignored_versions(possible_releases)
          possible_releases = filter_lower_versions(possible_releases)

          possible_releases.find { |r| package_details_fetcher.released?(r.version) }
        end

        private

        sig { returns(Package::PackageDetailsFetcher) }
        def package_details_fetcher
          @package_details_fetcher ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          )
        end
      end
    end
  end
end
