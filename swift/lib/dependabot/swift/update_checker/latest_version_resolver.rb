# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/swift/file_parser/dependency_parser"
require "dependabot/swift/file_updater/lockfile_updater"
require "dependabot/swift/package/package_details_fetcher"
require "sorbet-runtime"
require "dependabot/git_commit_checker"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionResolver
        extend T::Sig

        DAY_IN_SECONDS = T.let(24 * 60 * 60, Integer)

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
            git_commit_checker: Dependabot::GitCommitChecker
          ).void
        end
        def initialize(dependency:, credentials:, cooldown_options:, git_commit_checker:)
          @dependency = dependency
          @credentials = credentials
          @cooldown_options = cooldown_options
          @git_commit_checker = T.let(
            git_commit_checker,
            Dependabot::GitCommitChecker
          )
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options

        sig { returns(Dependabot::GitCommitChecker) }
        attr_reader :git_commit_checker

        # Return latest version tag for the dependency, it removes tags that are in cooldown period
        # and returns the latest version tag that is not in cooldown period. If an exception occurs
        # it will return the latest version tag from the git_commit_checker. as it was before
        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          # step one fetch allowed version tags and
          return git_commit_checker.local_tag_for_latest_version unless cooldown_enabled?

          allowed_version_tags = git_commit_checker.allowed_version_tags
          select_version_tags_in_cooldown_period&.each do |tag_name|
            # filter out if name is in cooldown period
            allowed_version_tags.reject! do |gitref_filtered|
              gitref_filtered.name == tag_name
            end
          end

          git_commit_checker.max_local_tag(allowed_version_tags)
        rescue StandardError => e
          Dependabot.logger.error("Error fetching latest version tag: #{e.message}")
          git_commit_checker.local_tag_for_latest_version
        end

        sig { returns(T.nilable(T::Array[String])) }
        def select_version_tags_in_cooldown_period
          version_tags_in_cooldown_period = T.let([], T::Array[String])

          package_details_fetcher.fetch_tag_and_release_date.each do |git_tag_with_detail|
            if check_if_version_in_cooldown_period?(git_tag_with_detail)
              version_tags_in_cooldown_period << git_tag_with_detail.tag
            end
          end
          version_tags_in_cooldown_period
        rescue StandardError => e
          Dependabot.logger.error("Error checking if version is in cooldown: #{e.message}")
          version_tags_in_cooldown_period
        end

        sig { params(tag_with_detail: Dependabot::GitTagWithDetail).returns(T::Boolean) }
        def check_if_version_in_cooldown_period?(tag_with_detail)
          return false unless tag_with_detail.release_date

          current_version = version_class.correct?(dependency.version) ? version_class.new(dependency.version) : nil
          days = cooldown_days_for(current_version, version_class.new(tag_with_detail.tag.delete("v")))

          # Calculate the number of seconds passed since the release
          passed_seconds = Time.now.to_i - release_date_to_seconds(tag_with_detail.release_date)
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
          return 0 unless cooldown_enabled?

          cooldown = T.must(cooldown_options)
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

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { params(release_date: T.nilable(String)).returns(Integer) }
        def release_date_to_seconds(release_date)
          return 0 unless release_date

          Time.parse(release_date).to_i
        rescue ArgumentError => e
          Dependabot.logger.error("Invalid release date format: #{release_date} and error: #{e.message}")
          0 # Default to 360 days in seconds if parsing fails, so that it will not be in cooldown
        end

        sig { returns(Package::PackageDetailsFetcher) }
        def package_details_fetcher
          @package_details_fetcher ||= T.let(
            Package::PackageDetailsFetcher.new(
              dependency: dependency,
              credentials: credentials,
              git_commit_checker: git_commit_checker
            ), T.nilable(Package::PackageDetailsFetcher)
          )
        end

        sig { returns(T::Boolean) }
        def cooldown_enabled?
          return false if cooldown_options.nil?

          cooldown = T.must(cooldown_options)
          cooldown.default_days.to_i.positive? ||
            cooldown.semver_major_days.to_i.positive? ||
            cooldown.semver_minor_days.to_i.positive? ||
            cooldown.semver_patch_days.to_i.positive?
        end
      end
    end
  end
end
