# typed: strong
# frozen_string_literal: true

require "dependabot/helm/package/package_details_fetcher"
require "sorbet-runtime"
require "dependabot/git_commit_checker"
require "dependabot/helm/version"

module Dependabot
  module Helm
    class LatestVersionResolver
      extend T::Sig

      DAY_IN_SECONDS = T.let(24 * 60 * 60, Integer)

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

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      # To filter versions in cooldown period based on version tags from registry call
      sig { params(versions: T::Array[String], repo_name: String).returns(T::Array[String]) }
      def filter_versions_in_cooldown_period_from_chart(versions, repo_name)
        return versions unless cooldown_enabled?

        Dependabot.logger.info("Filtering versions in cooldown period from chart: #{repo_name}")
        return versions unless select_tags_which_in_cooldown_from_chart(repo_name).nil?

        # sort the allowed version tags by name in descending order
        select_tags_which_in_cooldown_from_chart(repo_name)&.each do |tag_name|
          # Iterate through versions and filter out those matching the tag_name
          versions.reject! do |version|
            version == tag_name
          end
        end
        Dependabot.logger.info("Allowed version tags after filtering versions in cooldown:
              #{versions.map(&:to_s).join(', ')}")
        versions
      rescue StandardError => e
        Dependabot.logger.error("Error filter_versions_in_cooldown_period_from_chart(versions): #{e.message}")
        versions
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

      sig { params(repo_name: String).returns(T.nilable(T::Array[String])) }
      def select_tags_which_in_cooldown_from_chart(repo_name)
        version_tags_in_cooldown_from_chart = T.let([], T::Array[String])

        begin
          package_details_fetcher.fetch_tag_and_release_date_from_chart(repo_name).each do |git_tag_with_detail|
            if check_if_version_in_cooldown_period?(T.must(git_tag_with_detail.release_date))
              version_tags_in_cooldown_from_chart << git_tag_with_detail.tag
            end
          end
          version_tags_in_cooldown_from_chart
        rescue StandardError => e
          Dependabot.logger.error("Error checking if version is in cooldown: #{e.message}")
          version_tags_in_cooldown_from_chart
        end
      end

      sig { returns(Package::PackageDetailsFetcher) }
      def package_details_fetcher
        @package_details_fetcher ||= T.let(
          Package::PackageDetailsFetcher.new(
            dependency: dependency,
            credentials: credentials
          ), T.nilable(Package::PackageDetailsFetcher)
        )
      end

      sig { returns(T::Boolean) }
      def cooldown_enabled?
        Dependabot::Experiments.enabled?(:enable_cooldown_for_helm)
      end

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials
    end
  end
end
