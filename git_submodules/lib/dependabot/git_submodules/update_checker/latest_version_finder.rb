# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/version_filters"
require "dependabot/package/package_latest_version_finder"
require "dependabot/git_submodules/update_checker"
require "dependabot/git_submodules/package/package_details_fetcher"

module Dependabot
  module GitSubmodules
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(dependency:, credentials:, cooldown_options:)
          @dependency = dependency
          @credentials = credentials
          @cooldown_options = cooldown_options
        end

        sig { returns(T.nilable(String)) }
        def latest_tag
          releases = version_list

          releases = filter_by_cooldown(T.must(releases))

          # if there are no releases after applying filters, we fallback to the current tag to avoid empty results
          releases = apply_post_fetch_latest_versions_filter(releases)
          releases.max_by(&:version)&.tag
        end

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def version_list
          @version_list ||=
            T.let(Package::PackageDetailsFetcher.new(
              dependency: dependency,
              credentials: credentials
            ).available_versions, T.nilable(T::Array[Dependabot::Package::PackageRelease]))
        end

        sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
        def in_cooldown_period?(release)
          unless release.released_at
            Dependabot.logger.info("Release date not available for ref tag #{release.tag}")
            return false
          end

          days = cooldown_days
          passed_seconds = Time.now.to_i - release.released_at.to_i
          passed_days = passed_seconds / DAY_IN_SECONDS

          if passed_days < days
            Dependabot.logger.info("Filtered #{release.tag}, Released on: " \
                                   "#{T.must(release.released_at).strftime('%Y-%m-%d')} " \
                                   "(#{passed_days}/#{days} cooldown days)")
          end

          passed_seconds < days * DAY_IN_SECONDS
        end

        sig do
          returns(Integer)
        end
        def cooldown_days
          cooldown = @cooldown_options
          return 0 if cooldown.nil?
          return 0 unless cooldown_enabled?
          return 0 unless cooldown.included?(dependency.name)

          return cooldown.default_days if cooldown.default_days.positive?
          return cooldown.semver_major_days if cooldown.semver_major_days.positive?
          return cooldown.semver_minor_days if cooldown.semver_minor_days.positive?
          return cooldown.semver_patch_days if cooldown.semver_patch_days.positive?

          cooldown.default_days
        end

        sig { returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_latest_versions_filter(releases)
          if releases.empty?
            Dependabot.logger.info("No releases found for #{dependency.name} after applying filters.")
            return releases
          end

          releases << Dependabot::Package::PackageRelease.new(
            version: GitSubmodules::Version.new("0.0.0-0.0"), # Lower than versions from package_details_fetcher
            tag: dependency.version
          )

          releases
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options
        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end
      end
    end
  end
end
