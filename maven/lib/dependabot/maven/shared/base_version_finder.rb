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

        VersionDetails = T.type_alias do
          {
            version: Dependabot::Version,
            source_url: T.nilable(String)
          }
        end

        sig { returns(T.nilable(VersionDetails)) }
        def latest_version_details
          release = fetch_latest_release
          release&.version ? { version: release.version, source_url: release.url } : nil
        end

        sig { returns(T.nilable(VersionDetails)) }
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
          possible_releases_reverse = possible_releases.reverse

          return possible_releases_reverse.find { |r| released?(r.version) } unless cooldown_options

          cooldown_filtered_releases = 0
          latest_release = possible_releases_reverse.find do |release|
            if in_cooldown_period?(release)
              Dependabot.logger.info("Filtered out (cooldown) : #{release}")
              cooldown_filtered_releases += 1
              next false
            end

            released?(release.version)
          end

          if cooldown_filtered_releases.positive?
            Dependabot.logger.info(
              "Filtered out #{cooldown_filtered_releases} version(s) due to cooldown"
            )
          end

          latest_release ||= current_version_fallback_release(
            possible_releases_reverse, cooldown_filtered_releases
          )
          latest_release
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

        # When every candidate was filtered out by cooldown, stay on the current
        # version (if released) instead of reporting no latest version at all.
        sig do
          params(
            possible_releases: T::Array[Dependabot::Package::PackageRelease],
            cooldown_filtered_releases: Integer
          ).returns(T.nilable(Dependabot::Package::PackageRelease))
        end
        def current_version_fallback_release(possible_releases, cooldown_filtered_releases)
          return if possible_releases.empty?
          return unless cooldown_filtered_releases == possible_releases.length

          current_version_str = dependency.version
          return unless current_version_str

          Dependabot.logger.info(
            "All versions filtered by cooldown for #{dependency.name}, " \
            "falling back to current version #{current_version_str}"
          )

          current_release = Dependabot::Package::PackageRelease.new(
            version: version_class.new(current_version_str),
            released_at: nil,
            tag: nil
          )
          current_release if released?(current_release.version)
        end

        sig { abstract.params(version: Dependabot::Version).returns(T::Boolean) }
        def released?(version); end
      end
    end
  end
end
