# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/go_modules/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/go_modules/requirement"
require "dependabot/go_modules/resolvability_errors"
require "dependabot/go_modules/package/package_details_fetcher"
require "dependabot/package/package_latest_version_finder"

module Dependabot
  module GoModules
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        RESOLVABILITY_ERROR_REGEXES = T.let(
          [
            # Package url/proxy doesn't include any redirect meta tags
            /no go-import meta tags/,
            # Package url 404s
            /404 Not Found/,
            /Repository not found/,
            /unrecognized import path/,
            /malformed module path/,
            # (Private) module could not be fetched
            /module .*: git ls-remote .*: exit status 128/m
          ].freeze,
          T::Array[Regexp]
        )
        # The module was retracted from the proxy
        # OR the version of Go required is greater than what Dependabot supports
        # OR other go.mod version errors
        INVALID_VERSION_REGEX = /(go: loading module retractions for)|(version "[^"]+" invalid)/m
        PSEUDO_VERSION_REGEX = /\b\d{14}-[0-9a-f]{12}$/

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            goprivate: String,
            raise_on_ignored: T::Boolean,
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          )
            .void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          goprivate:,
          raise_on_ignored: false,
          cooldown_options: nil
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
          @raise_on_ignored    = raise_on_ignored
          @goprivate           = goprivate
          @cooldown_options    = cooldown_options
          super(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            cooldown_options: cooldown_options,
            raise_on_ignored: raise_on_ignored,
            options: {}
          )
        end

        sig do
          override.params(language_version: T.nilable(T.any(String, Dependabot::Version)))
                  .returns(T.nilable(Dependabot::Version))
        end
        def latest_version(language_version: nil)
          @latest_version ||= T.let(fetch_latest_version(language_version: language_version),
                                    T.nilable(Dependabot::Version))
        end

        sig do
          override.params(language_version: T.nilable(T.any(String, Dependabot::Version)))
                  .returns(T.nilable(Dependabot::Version))
        end
        def lowest_security_fix_version(language_version: nil)
          @lowest_security_fix_version ||= T.let(fetch_lowest_security_fix_version(language_version: language_version),
                                                 T.nilable(Dependabot::Version))
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(String) }
        attr_reader :goprivate

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def available_versions_details
          @available_versions_details ||= T.let(Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            goprivate: goprivate
          ).fetch_available_versions, T.nilable(T::Array[Dependabot::Package::PackageRelease]))
        end

        # rubocop:disable Lint/UnusedMethodArgument
        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(language_version: nil)
          candidate_versions = available_versions_details
          candidate_versions = filter_incompatible_versions(candidate_versions)
          candidate_versions = filter_prerelease_versions(candidate_versions)
          candidate_versions = filter_ignored_versions(candidate_versions)
          candidate_versions = lazy_filter_cooldown_versions(candidate_versions)
          # Adding the psuedo-version to the list to avoid downgrades
          if PSEUDO_VERSION_REGEX.match?(dependency.version)
            candidate_versions << Dependabot::Package::PackageRelease.new(
              version: GoModules::Version.new(dependency.version)
            )
          end

          candidate_versions.max_by(&:version)&.version
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_incompatible_versions(releases)
          # If GOPRIVATE="*", incompatible versions are already filtered by Go
          # This method can provide additional filtering if needed
          env = { "GOPRIVATE" => @goprivate }
          begin
            update_json = SharedHelpers.run_shell_command(
              "go list -m -u -json #{dependency.name}@#{dependency.version}",
              fingerprint: "go list -m -u -json <dependency_name>",
              env: env
            )

            parsed_json = JSON.parse(update_json)
            updated_version = parsed_json.dig("Update", "Version")

            if updated_version
              # Filter out versions greater than Go's recommendation
              releases.select do |release|
                release.version <= GoModules::Version.new(updated_version)
              end

            else
              # If no update recommendation, return all releases
              releases
            end
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
            Dependabot.logger.warn("Failed to get Go update recommendation: #{e.message}")
            # If command fails, -U may not be applicable to the dependency and return all releases
            releases
          end
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease], check_max: T::Boolean)
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def lazy_filter_cooldown_versions(releases, check_max: true)
          return releases unless cooldown_enabled?
          return releases unless cooldown_options

          Dependabot.logger.info("Initializing cooldown filter")

          sorted_releases = if check_max
                              releases.sort_by(&:version).reverse
                            else
                              releases.sort_by(&:version)
                            end

          filtered_versions = []
          cooldown_filtered_versions = 0

          # Iterate through the sorted versions lazily, filtering out cooldown versions
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
          env = { "GOPRIVATE" => @goprivate }

          begin
            release_info = SharedHelpers.run_shell_command(
              "go list -m -json #{dependency.name}@#{release.details.[]('version_string')}",
              fingerprint: "go list -m -json <dependency_name>",
              env: env
            )
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
            Dependabot.logger.info("Error while fetching release date info: #{e.message}")
            return false
          end

          release.instance_variable_set(
            :@released_at, JSON.parse(release_info)["Time"] ? Time.parse(JSON.parse(release_info)["Time"]) : nil
          )

          return false unless release.released_at

          current_version = version_class.correct?(dependency.version) ? version_class.new(dependency.version) : nil
          days = cooldown_days_for(current_version, release.version)

          # Calculate the number of seconds passed since the release
          passed_seconds = Time.now.to_i - release.released_at.to_i
          passed_days = passed_seconds / DAY_IN_SECONDS

          if passed_days < days
            Dependabot.logger.info("Version #{release.version}, Release date: #{release.released_at}." \
                                   " Days since release: #{passed_days} (cooldown days: #{days})")
          end

          # Check if the release is within the cooldown period
          passed_seconds < days * DAY_IN_SECONDS
        end
        # rubocop:enable Metrics/AbcSize

        sig do
          override.returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def package_details
          @package_details ||= T.let(
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: available_versions_details.reverse.uniq(&:version)
            ), T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_lowest_security_fix_version(language_version: nil)
          relevant_versions = available_versions_details
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(relevant_versions,
                                                                                                    security_advisories)
          relevant_versions = filter_ignored_versions(relevant_versions)
          relevant_versions = filter_lower_versions(relevant_versions)

          relevant_versions.min_by(&:version)&.version
        end
        # rubocop:enable Lint/UnusedMethodArgument

        sig { returns(T::Boolean) }
        def wants_prerelease?
          @wants_prerelease ||= T.let(
            begin
              current_version = dependency.numeric_version
              !current_version&.prerelease?.nil?
            end,
            T.nilable(T::Boolean)
          )
        end
      end
    end
  end
end
