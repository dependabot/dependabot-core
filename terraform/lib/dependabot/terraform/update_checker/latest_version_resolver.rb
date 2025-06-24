# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/terraform/package/package_details_fetcher"
require "sorbet-runtime"
require "dependabot/git_commit_checker"

module Dependabot
  module Terraform
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
        # and returns the latest version tag that is not in cooldown period. If exception occurs
        # it will return the latest version tag from the git_commit_checker. as it was before
        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          # step one fetch allowed version tags and
          allowed_version_tags = git_commit_checker.allowed_version_tags
          begin
            # sort the allowed version tags by name in descending order
            select_version_tags_in_cooldown_period&.each do |tag_name|
              # filter out if name is not in cooldown period
              allowed_version_tags.reject! do |gitref_filtered|
                true if gitref_filtered.name == tag_name
              end
            end
            Dependabot.logger.info("Allowed version tags after filtering versions in cooldown:
              #{allowed_version_tags.map(&:name).join(', ')}")
            git_commit_checker.max_local_tag(allowed_version_tags)
          rescue StandardError => e
            Dependabot.logger.error("Error fetching latest version tag: #{e.message}")
            git_commit_checker.local_tag_for_latest_version
          end
        end

        # To filter versions in cooldown period based on version tags from registry call
        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_versions_in_cooldown_period_from_provider(versions)
          # to make call for registry to get the versions
          # step one fetch allowed version tags and

          # sort the allowed version tags by name in descending order
          select_tags_which_in_cooldown_from_provider&.each do |tag_name|
            # Iterate through versions and filter out those matching the tag_name
            versions.reject! do |version|
              version.to_s == tag_name
            end
          end
          Dependabot.logger.info("Allowed version tags after filtering versions in cooldown:
                #{versions.map(&:to_s).join(', ')}")
          versions
        rescue StandardError => e
          Dependabot.logger.error("Error filter_versions_in_cooldown_period_from_provider(versions): #{e.message}")
          versions
        end

        # To filter versions in cooldown period based on version tags from registry call
        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_versions_in_cooldown_period_from_module(versions)
          # to make call for registry to get the versions
          # step one fetch allowed version tags and

          # sort the allowed version tags by name in descending order
          select_tags_which_in_cooldown_from_module&.each do |tag_name|
            # Iterate through versions and filter out those matching the tag_name
            versions.reject! do |version|
              version.to_s == tag_name
            end
          end
          Dependabot.logger.info("filter_versions_in_cooldown_period_from_module::
              Allowed version tags after filtering versions in cooldown:#{versions.map(&:to_s).join(', ')}")
          versions
        rescue StandardError => e
          Dependabot.logger.error("Error fetching latest version tag: #{e.message}")
          versions
        end

        sig { returns(T.nilable(T::Array[String])) }
        def select_version_tags_in_cooldown_period
          version_tags_in_cooldown_period = T.let([], T::Array[String])

          package_details_fetcher.fetch_tag_and_release_date.each do |git_tag_with_detail|
            if check_if_version_in_cooldown_period?(T.must(git_tag_with_detail.release_date))
              version_tags_in_cooldown_period << git_tag_with_detail.tag
            end
          end
          version_tags_in_cooldown_period
        rescue StandardError => e
          Dependabot.logger.error("Error checking if version is in cooldown: #{e.message}")
          version_tags_in_cooldown_period
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

        sig { returns(T.nilable(T::Array[String])) }
        def select_tags_which_in_cooldown_from_provider
          version_tags_in_cooldown_from_provider = T.let([], T::Array[String])

          package_details_fetcher.fetch_tag_and_release_date_from_provider.each do |git_tag_with_detail|
            if check_if_version_in_cooldown_period?(T.must(git_tag_with_detail.release_date))
              version_tags_in_cooldown_from_provider << git_tag_with_detail.tag
            end
          end
          version_tags_in_cooldown_from_provider
        rescue StandardError => e
          Dependabot.logger.error("Error checking if version is in cooldown: #{e.message}")
          version_tags_in_cooldown_from_provider
        end

        sig { returns(T.nilable(T::Array[String])) }
        def select_tags_which_in_cooldown_from_module
          version_tags_in_cooldown_from_module = T.let([], T::Array[String])

          package_details_fetcher.fetch_tag_and_release_date_from_module.each do |git_tag_with_detail|
            if check_if_version_in_cooldown_period?(T.must(git_tag_with_detail.release_date))
              version_tags_in_cooldown_from_module << git_tag_with_detail.tag
            end
          end
          version_tags_in_cooldown_from_module
        rescue StandardError => e
          Dependabot.logger.error("Error checking if version is in cooldown: #{e.message}")
          version_tags_in_cooldown_from_module
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
