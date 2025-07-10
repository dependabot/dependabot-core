# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

require "open3"
require "shellwords"
require "dependabot/errors"
require "dependabot/package/package_latest_version_finder"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/version_filters"
require "dependabot/devcontainers/file_parser"
require "dependabot/devcontainers/package/package_details_fetcher"
require "dependabot/devcontainers/requirement"
require "dependabot/devcontainers/update_checker"

module Dependabot
  module Devcontainers
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            raise_on_ignored: T::Boolean,
            options: T::Hash[Symbol, T.untyped],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          raise_on_ignored:,
          options: {},
          cooldown_options: nil
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
          @raise_on_ignored    = raise_on_ignored
          @options             = options
          @cooldown_options = cooldown_options
          super
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options
        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions
        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories
        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end

        sig { returns(T.nilable(T::Array[Dependabot::Version])) }
        def release_versions
          releases = package_releases

          releases = filter_ignored_versions(T.must(releases))
          releases = filter_lower_versions(releases)
          releases = lazy_filter_cooldown_versions(releases)

          releases = releases.sort_by(&:version)

          if releases.empty?
            Dependabot.logger.info("No release candidates found for #{dependency.name}, returning current version")
            return Array(current_version)
          end

          releases.map(&:version)
        end

        private

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def package_releases
          @package_releases = T.let(Dependabot::Devcontainers::Package::PackageDetailsFetcher
            .new(dependency: dependency)
            .fetch_package_releases, T.nilable(T::Array[Dependabot::Package::PackageRelease]))
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def current_version
          @current_version ||=
            T.let(
              dependency.numeric_version,
              T.nilable(Dependabot::Version)
            )
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def lazy_filter_cooldown_versions(releases)
          return releases unless cooldown_enabled?
          return releases unless cooldown_options

          Dependabot.logger.info("Initializing cooldown filter")

          unless releases.any?
            Dependabot.logger.info("No releases found, skipping cooldown filtering")
            return releases
          end

          sorted_releases = releases.sort_by(&:version).reverse
          filtered_versions = []
          cooldown_filtered_versions = 0

          sorted_releases.each do |release|
            if in_cooldown_period?(release)
              Dependabot.logger.info("Filtered out (cooldown) : #{release}")
              cooldown_filtered_versions += 1
              next
            end

            filtered_versions << release
            break
          end
          Dependabot.logger.info("Filtered out #{cooldown_filtered_versions} version(s) due to cooldown")

          filtered_versions
        end

        # rubocop:disable Metrics/AbcSize
        sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
        def in_cooldown_period?(release)
          release = T.let(Dependabot::Devcontainers::Package::PackageDetailsFetcher
          .new(dependency: dependency)
          .fetch_release_metadata(release: release), T.nilable(Dependabot::Package::PackageRelease))

          unless T.must(release).released_at
            Dependabot.logger.info(
              "Release date unavailable for #{T.must(release).version}. Cooldown filtering not possible"
            )
            return false
          end

          current_version = version_class.correct?(dependency.version) ? version_class.new(dependency.version) : nil

          days = cooldown_days_for(current_version, T.must(release).version)
          passed_seconds = Time.now.to_i - T.must(release).released_at.to_i
          passed_days = passed_seconds / DAY_IN_SECONDS

          if passed_days < days
            Dependabot.logger.info("Version #{T.must(release).version}, Release date: #{T.must(release).released_at}." \
                                   " Days since release: #{passed_days} (cooldown days: #{days})")
          end

          passed_seconds < days * DAY_IN_SECONDS
        end
        # rubocop:enable Metrics/AbcSize
      end
    end
  end
end
