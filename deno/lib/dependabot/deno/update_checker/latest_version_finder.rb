# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/package/package_latest_version_finder"
require "dependabot/package/package_details"
require "dependabot/deno/update_checker"
require "dependabot/deno/package/package_details_fetcher"

module Dependabot
  module Deno
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        private

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= T.let(
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: Package::PackageDetailsFetcher.new(
                dependency: dependency
              ).available_versions
            ),
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end
      end
    end
  end
end
