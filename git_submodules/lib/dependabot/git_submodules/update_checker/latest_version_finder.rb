# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/cooldown_calculation"
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
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(String))
        end
        def latest_tag(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          releases = version_list

          releases = filter_by_cooldown(T.must(releases))
          releases = filter_ignored_versions(releases)

          # if there are no releases after applying filters, we fallback to the current tag to avoid empty results
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

        sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
        def in_cooldown_period?(release)
          unless release.released_at
            Dependabot.logger.info("Release date not available for ref tag #{release.tag}")
            return false
          end

          days = cooldown_days
          in_cooldown = Dependabot::UpdateCheckers::CooldownCalculation
                        .within_cooldown_window?(T.must(release.released_at), days)

          if in_cooldown
            passed_days = (Time.now.to_i - release.released_at.to_i) / (24 * 60 * 60)
            Dependabot.logger.info(
              "Filtered #{release.tag}, Released on: " \
              "#{T.must(release.released_at).strftime('%Y-%m-%d')} " \
              "(#{passed_days}/#{days} cooldown days)"
            )
          end

          in_cooldown
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

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end
      end
    end
  end
end
