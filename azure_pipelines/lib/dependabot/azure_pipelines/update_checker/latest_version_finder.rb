# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/package/package_details"
require "dependabot/package/package_latest_version_finder"
require "dependabot/update_checkers/base"

require "dependabot/azure_pipelines/package/package_details_fetcher"
require "dependabot/azure_pipelines/requirement"
require "dependabot/azure_pipelines/version"

module Dependabot
  module AzurePipelines
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= T.let(
            Dependabot::AzurePipelines::Package::PackageDetailsFetcher.new(
              dependency: dependency,
              credentials: credentials,
              fetch_release_dates: !cooldown_options.nil?
            ).fetch,
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        protected

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_latest_versions_filter(releases)
          filter_deprecated_versions(releases)
        end

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_lowest_security_fix_versions_filter(releases)
          filter_deprecated_versions(releases)
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled? = true

        private

        # Microsoft marks superseded task versions as deprecated in `task.json`. Moving
        # a pipeline onto one would be a pointless churn, so they are never offered as
        # a target. A pipeline already sitting on a deprecated version keeps it: there
        # is nothing better to move it to, and rewriting it back to itself helps nobody.
        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_deprecated_versions(releases)
          filtered = releases.reject do |release|
            deprecated?(release) && release.version.to_s != dependency.version
          end

          if releases.count > filtered.count
            Dependabot.logger.info("Filtered out #{releases.count - filtered.count} deprecated task versions")
          end

          filtered
        end

        sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
        def deprecated?(release)
          T.cast(release.details["deprecated"], T.nilable(T::Boolean)) == true
        end
      end
    end
  end
end
