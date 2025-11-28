# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/uv/update_checker"
require "dependabot/uv/package"
require "dependabot/package/package_latest_version_finder"

module Dependabot
  module Uv
    class UpdateChecker
      # UV uses the same PyPI registry for package lookups as Python
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          override.returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def package_details
          @package_details ||= T.let(
            Package::PackageDetailsFetcher.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials
            ).fetch,
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end
      end
    end
  end
end
