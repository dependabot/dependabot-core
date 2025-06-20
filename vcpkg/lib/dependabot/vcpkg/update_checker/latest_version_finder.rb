# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers/base"
require "dependabot/package/package_latest_version_finder"

require "dependabot/vcpkg/package/package_details_fetcher"
require "dependabot/vcpkg/requirement"
require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= T.let(
            Package::PackageDetailsFetcher.new(dependency: dependency).fetch,
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig { returns(T.nilable(String)) }
        def latest_tag
          available_versions
            &.then { |releases| filter_by_cooldown(releases) }
            &.max_by(&:version)
            &.details
            &.[]("tag_sha")
        end

        private

        sig { override.returns(T::Boolean) }
        def cooldown_enabled? = Dependabot::Experiments.enabled?(:enable_cooldown_for_vcpkg)
      end
    end
  end
end
