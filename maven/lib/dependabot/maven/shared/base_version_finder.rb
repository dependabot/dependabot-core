# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/maven/shared/shared_version_finder"

module Dependabot
  module Maven
    module Shared
      # Intermediate class for ecosystems (Maven, SBT) that use a package_details-based
      # release pipeline with HEAD-check verification. Gradle uses its own filter chain
      # and inherits directly from SharedVersionFinder.
      class BaseVersionFinder < SharedVersionFinder
        extend T::Sig
        extend T::Helpers

        abstract!

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
            released?(r.version)
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

          possible_releases.find { |r| released?(r.version) }
        end

        private

        sig { abstract.params(version: Dependabot::Version).returns(T::Boolean) }
        def released?(version); end
      end
    end
  end
end
