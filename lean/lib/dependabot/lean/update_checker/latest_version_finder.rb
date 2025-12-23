# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/package/package_latest_version_finder"
require "dependabot/lean"
require "dependabot/lean/version"
require "dependabot/lean/package/package_details_fetcher"

module Dependabot
  module Lean
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= T.let(
            Package::PackageDetailsFetcher.new(
              dependency: dependency,
              credentials: credentials
            ).fetch,
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig { override.returns(T::Array[Dependabot::Package::PackageRelease]) }
        def available_versions
          details = package_details
          return [] unless details

          releases = details.releases.sort_by(&:version).reverse

          # Filter based on current version type
          current_is_prerelease = current_version_prerelease?

          releases.select do |release|
            version = T.cast(release.version, Lean::Version)

            # If user is on a stable version, only offer stable releases
            # If user is on an RC, offer both RCs and stable releases
            if current_is_prerelease
              true # Offer all versions
            else
              !version.prerelease? # Only offer stable versions
            end
          end
        end

        private

        sig { returns(T::Boolean) }
        def current_version_prerelease?
          current = dependency.version
          return false unless current

          version = Lean::Version.new(current)
          version.prerelease?
        rescue ArgumentError
          false
        end
      end
    end
  end
end
