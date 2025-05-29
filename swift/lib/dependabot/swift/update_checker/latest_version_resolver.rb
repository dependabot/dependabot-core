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

        # Return latest version tag for the dependency, it removes tags that are in cooldown period
        # and returns the latest version tag that is not in cooldown period. If eexception occurs
        # it will return the latest version tag from the git_commit_checker. as it was before
        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          # step one fetch allowed version tags and
          allowed_version_tags = git_commit_checker.allowed_version_tags
          begin
            # sort the allowed version tags by name in descending order
            allowed_version_tags = allowed_version_tags.sort_by(&:name).reverse
            allowed_v_tags_after_filtering_cooldown = allowed_version_tags
            allowed_version_tags.each do |gitref|
              # Perform operations on each gitref
              Dependabot.logger.info("Processing gitref: #{gitref.name}")
              break unless check_if_version_is_in_cooldown?(gitref)

              # filter out if name is not in cooldown period
              allowed_v_tags_after_filtering_cooldown.reject do |gitref_filtered|
                gitref_filtered.name == gitref.name
              end
            end
            git_commit_checker.max_local_tag(allowed_v_tags_after_filtering_cooldown)
          rescue StandardError => e
            Dependabot.logger.error("Error fetching latest version tag: #{e.message}")
            git_commit_checker.local_tag_for_latest_version
          end
        end

        # This method will return true if the tag is in cooldown period else false.
        sig { params(tag: Dependabot::GitRef).returns(T::Boolean) }
        def check_if_version_is_in_cooldown?(tag)
          # to do check if the tag is in cooldown period
          # call another method to fethch release details from the GitHub API
          return false unless cooldown_enabled?

          # rubocop:disable Style/Next
          package_details_fetcher.fetch_tag_and_release_date.each do |git_tag_with_detail|
            Dependabot.logger.info("Checking if tag #{tag.name} is in cooldown period")
            if git_tag_with_detail.tag == tag.name &&
               check_if_version_in_cooldown_period?(git_tag_with_detail.release_date)
              Dependabot.logger.info("Tag #{tag.name} is in cooldown period")
              return true
            end
          end

          false
          # rubocop:enable Style/Next
        rescue StandardError => e
          Dependabot.logger.error("Error checking if version is in cooldown: #{e.message}")
          false
        end

        sig { params(release_date: String).returns(T::Boolean) }
        def check_if_version_in_cooldown_period?(release_date)
          return false unless release_date.length.positive?

          cooldown = @cooldown_options
          return false unless cooldown

          return false if cooldown.nil?

          # Get maximum cooldown days based on semver parts
          days = [cooldown.default_days, cooldown.semver_major_days].max
          days = cooldown.semver_minor_days unless days > cooldown.semver_minor_days
          days = cooldown.semver_patch_days unless days > cooldown.semver_patch_days
          Dependabot.logger.info("Cooldown days: #{days} and release date: #{release_date}")
          # Calculate the number of seconds passed since the release
          passed_seconds = Time.now.to_i - release_date_to_seconds(release_date)
          # Check if the release is within the cooldown period
          passed_seconds < days * DAY_IN_SECONDS
        end

        sig { params(release_date: String).returns(Integer) }
        def release_date_to_seconds(release_date)
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
          Dependabot::Experiments.enabled?(:enable_cooldown_for_swift)
        end

        sig { returns(Dependabot::GitCommitChecker) }
        attr_reader :git_commit_checker

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
      end
    end
  end
end
