# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/package/package_latest_version_finder"
require "dependabot/powershell/package/package_details_fetcher"
require "dependabot/powershell/requirement"
require "dependabot/powershell/update_checker"
require "dependabot/powershell/version"

module Dependabot
  module Powershell
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= Dependabot::Powershell::Package::PackageDetailsFetcher
                               .new(dependency: dependency)
                               .fetch
        end

        sig { params(version: String).returns(T.nilable(String)) }
        def manifest_guid_for(version)
          Dependabot::Powershell::Package::PackageDetailsFetcher
            .new(dependency: dependency)
            .manifest_guid_for(version)
        end

        protected

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end
      end
    end
  end
end
