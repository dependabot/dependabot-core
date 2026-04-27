# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/package/package_latest_version_finder"
require "dependabot/package/package_details"
require "dependabot/nix/update_checker"
require "dependabot/nix/package/package_details_fetcher"

module Dependabot
  module Nix
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        # All Nix versions are pseudo-versions with prerelease segments (0.0.0-0.N),
        # so we must always include prereleases to avoid filtering everything out.
        sig { override.returns(T::Boolean) }
        def wants_prerelease?
          true
        end

        protected

        sig do
          override.params(releases: T::Array[Dependabot::Package::PackageRelease])
                  .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_by_cooldown(releases)
          return releases unless cooldown_enabled?
          return releases unless cooldown_options

          filtered = releases.reject { |release| in_cooldown_period?(release) }

          if releases.count > filtered.count
            Dependabot.logger.info("Filtered out #{releases.count - filtered.count} versions due to cooldown")
          end

          if filtered.empty? && !releases.empty? && dependency.version
            Dependabot.logger.info(
              "All versions filtered by cooldown for #{dependency.name}, " \
              "falling back to current version #{dependency.version}"
            )

            return [current_dependency_release]
          end

          filtered
        end

        private

        sig do
          override.params(releases: T::Array[Dependabot::Package::PackageRelease])
                  .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_latest_versions_filter(releases)
          if releases.empty?
            Dependabot.logger.info("No releases found for #{dependency.name} after applying filters.")
            return releases
          end

          # Fallback so the current version is always in the candidate set
          current_release = current_dependency_release
          releases << current_release unless releases.any? { |r| r.version == current_release.version }
          releases
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= T.let(
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: Package::PackageDetailsFetcher.new(
                dependency: dependency,
                credentials: credentials
              ).available_versions || []
            ),
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig { returns(Dependabot::Package::PackageRelease) }
        def current_dependency_release
          Dependabot::Package::PackageRelease.new(
            version: Nix::Version.new("0.0.0-0.0"),
            tag: dependency.version
          )
        end
      end
    end
  end
end
