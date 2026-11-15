# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers/base"
require "dependabot/package/package_latest_version_finder"

require "dependabot/nimble/package/package_details_fetcher"
require "dependabot/nimble/requirement"
require "dependabot/nimble/version"

module Dependabot
  module Nimble
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= T.let(
            Package::PackageDetailsFetcher.new(dependency: dependency, credentials: credentials).fetch,
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled? = true
      end
    end
  end
end
