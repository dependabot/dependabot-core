# typed: strict
# frozen_string_literal: true

require "excon"
require "dependabot/pub/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "dependabot/pub/package/package_details_fetcher"
require "dependabot/package/package_latest_version_finder"
require "sorbet-runtime"

module Dependabot
  module Pub
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

        include Dependabot::Pub::Package

        DAY_IN_SECONDS = T.let(24 * 60 * 60, Integer)

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            options: T::Hash[Symbol, T.untyped],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions: [],
                       security_advisories: [], options: {},
                       cooldown_options: nil)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @ignored_versions = ignored_versions
          @security_advisories = security_advisories
          @options = options
          @cooldown_options = cooldown_options
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def current_report
          @current_report ||= T.let(T.must(PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            options: options
          ).report.find { |d| d["name"] == dependency.name }), T.nilable(T::Hash[String, T.untyped]))
        end

        sig { returns(T.nilable(String)) }
        def latest_version
          latest_version = current_report["latest"]
          return nil unless latest_version

          filter_cooldown_versions(latest_version)
        end

        sig { returns(T.nilable(String)) }
        def latest_resolvable_version
          latest_resolvable_version = current_report["singleBreaking"]&.find { |d| d["name"] == dependency.name }
          return nil unless latest_resolvable_version

          filter_cooldown_versions(latest_resolvable_version["version"])
        end

        sig { returns(T.nilable(String)) }
        def latest_resolvable_version_with_no_unlock
          version_with_no_unlock = current_report["compatible"]&.find { |d| d["name"] == dependency.name }
          return nil unless version_with_no_unlock

          filter_cooldown_versions(version_with_no_unlock["version"])
        end

        sig { returns(T.nilable(String)) }
        def latest_version_resolvable_with_full_unlock
          version_with_full_unlock = current_report["multiBreaking"]&.find { |d| d["name"] == dependency.name }
          return nil unless version_with_full_unlock

          filter_cooldown_versions(version_with_full_unlock["version"])
        end

        sig { returns(T.untyped) }
        def latest_version_resolvable_with_full_unlock_hash
          current_report["multiBreaking"]
        end

        sig { returns(T.untyped) }
        def latest_resolvable_version_hash
          current_report["singleBreaking"].find { |d| d["name"] == dependency.name }
        end

        private

        sig do
          params(
            unparsed_version: String
          ).returns(T.nilable(String))
        end
        def filter_cooldown_versions(unparsed_version)
          return unparsed_version unless cooldown_enabled?
          return unparsed_version unless cooldown_options

          @package_details ||= T.let(PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            options: options
          ).package_details_metadata, T.nilable(T::Array[Dependabot::Package::PackageRelease]))

          return unparsed_version unless @package_details.any?

          version_release = @package_details.find do |release|
            release.version == unparsed_version
          end

          return unparsed_version unless in_cooldown_period?(version_release)

          dependency.version
          rescue StandardError => e
            Dependabot.logger.error("Failed to filter cooldown versions for \"#{dependency.name}\": #{e.backtrace}")
            unparsed_version
        end

        sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
        def in_cooldown_period?(release)
          unless release.released_at
            Dependabot.logger.info("Release date not available for version #{release.version}")
            return false
          end

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

        sig do
          params(
            current_version: T.nilable(Dependabot::Version),
            new_version: Dependabot::Version
          ).returns(Integer)
        end
        def cooldown_days_for(current_version, new_version)
          cooldown = @cooldown_options
          return 0 if cooldown.nil?
          return 0 unless cooldown_enabled?
          return 0 unless cooldown.included?(dependency.name)
          return cooldown.default_days if current_version.nil?

          current_version_semver = current_version.semver_parts
          new_version_semver = new_version.semver_parts

          # If semver_parts is nil for either, return default cooldown
          return cooldown.default_days if current_version_semver.nil? || new_version_semver.nil?

          # Ensure values are always integers
          current_major, current_minor, current_patch = current_version_semver
          new_major, new_minor, new_patch = new_version_semver

          # Determine cooldown based on version difference
          return cooldown.semver_major_days if new_major > current_major
          return cooldown.semver_minor_days if new_minor > current_minor
          return cooldown.semver_patch_days if new_patch > current_patch

          cooldown.default_days
        end

        sig { returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

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
        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :options
        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options
      end
    end
  end
end
