# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/package/package_latest_version_finder"
require "dependabot/nix/update_checker"
require "dependabot/nix/package/package_details_fetcher"

module Dependabot
  module Nix
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { returns(T.nilable(String)) }
        def latest_tag
          releases = version_list
          return nil unless releases

          releases = filter_by_cooldown(releases)
          releases = filter_ignored_versions(releases)
          releases = apply_post_fetch_latest_versions_filter(releases)
          releases.max_by(&:version)&.tag
        end

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def version_list
          @version_list ||=
            T.let(
              Package::PackageDetailsFetcher.new(
                dependency: dependency,
                credentials: credentials
              ).available_versions,
              T.nilable(T::Array[Dependabot::Package::PackageRelease])
            )
        end

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
          releases << Dependabot::Package::PackageRelease.new(
            version: Nix::Version.new("0.0.0-0.0"),
            tag: dependency.version
          )
          releases
        end

        private

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end
      end
    end
  end
end
