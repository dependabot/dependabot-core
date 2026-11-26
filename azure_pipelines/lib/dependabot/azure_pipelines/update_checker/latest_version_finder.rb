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
              fetch_release_dates: !cooldown_options.nil?,
              cooldown_options: cooldown_options
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
          filter_deprecated_versions(filter_preview_versions(releases))
        end

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_lowest_security_fix_versions_filter(releases)
          filter_deprecated_versions(filter_preview_versions(releases))
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled? = true

        private

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_preview_versions(releases)
          return releases if wants_preview?

          filtered = releases.reject { |release| preview?(release) }
          if releases.count > filtered.count
            Dependabot.logger.info("Filtered out #{releases.count - filtered.count} preview task versions")
          end
          filtered
        end

        # Azure rejects prerelease suffixes in task pins. Preview opt-in must come
        # from metadata, using the newest release matching each pin's precision.
        sig { returns(T::Boolean) }
        def wants_preview?
          releases = available_versions || []
          pins = dependency.requirements.filter_map do |requirement|
            pin = requirement[:requirement]
            case pin
            when String then pin
            end
          end
          version = dependency.version
          pins << version if version

          pins.any? do |pin|
            next false unless Version.correct?(pin)

            version = Version.new(pin)
            current = releases.select do |release|
              Version.new(release.version.to_s).truncate(version.precision) == version
            end.max_by(&:version)
            current ? preview?(current) : false
          end
        end

        sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
        def preview?(release)
          T.cast(release.details["preview"], T.nilable(T::Boolean)) == true
        end

        # Microsoft marks superseded task versions as deprecated in `task.json`. Moving
        # a pipeline onto one would be a pointless churn, so they are never offered as
        # a target. A pipeline already sitting on a deprecated version keeps it: there
        # is nothing better to move it to, and rewriting it back to itself helps nobody.
        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_deprecated_versions(releases)
          # A deprecated task version also makes every earlier version deprecated.
          latest_deprecated_version = available_versions&.select do |release|
            deprecated?(release)
          end&.max_by(&:version)&.version
          filtered = releases.reject do |release|
            latest_deprecated_version && release.version <= latest_deprecated_version &&
              release.version.to_s != dependency.version
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
