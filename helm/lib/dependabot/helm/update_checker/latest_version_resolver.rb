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
      sig { params(tags: T::Array[String], repo_name: String).returns(T::Array[String]) }
      def filter_versions_in_cooldown_period_using_oci(tags, repo_name)
        # return tags unless cooldown_enabled?

        Dependabot.logger.info("Filtering versions in cooldown period from chart: #{repo_name}")
        return tags unless select_tags_which_in_cooldown_using_oci(tags, repo_name).nil?

        # sort the allowed version tags by name in descending order
        select_tags_which_in_cooldown_using_oci(tags, repo_name)&.each do |tag_name|
          # Iterate through versions and filter out those matching the tag_name
          tags.reject! do |version|
            version == tag_name
          end
        end
        Dependabot.logger.info("Allowed version tags after filtering versions in cooldown:
              #{tags.map(&:to_s).join(', ')}")
        tags
      rescue StandardError => e
        Dependabot.logger.error("Error filter_versions_in_cooldown_period_for_oci:: #{e.message}")
        tags
      end

      # To filter versions in cooldown period based on version tags from registry call
      sig do
        params(
          versions: T::Array[T::Hash[String, T.untyped]],
          repo_name: T.nilable(String)
        )
          .returns(T::Array[T::Hash[String, T.untyped]])
      end
      def fetch_tag_and_release_date_helm_chart(versions, repo_name)
        return versions unless repo_name.nil? || repo_name.empty?

        Dependabot.logger.info("Filtering versions in cooldown period from chart: #{repo_name}")
        return versions unless select_tags_which_in_cooldown_from_chart(T.must(repo_name)).nil?

        # Get the tags in cooldown once
        cooldown_tags = select_tags_which_in_cooldown_from_chart(T.must(repo_name))
        return versions if cooldown_tags.nil? || cooldown_tags.empty?

        # Filter out versions that are in the cooldown period
        # releases.reject do |release|
        # version_class.new(release["version"]) <= version_class.new(dependency.version) ||
        # ignore_requirements.any? { |r| r.satisfied_by?(version_class.new(release["version"])) }
        #  end
        versions.reject! do |release|
          cooldown_tags.any?(release["version"])
        end
        Dependabot.logger.info("Allowed version tags after filtering versions in cooldown:
              #{versions.map(&:to_s).join(', ')}")
        versions
      rescue StandardError => e
        Dependabot.logger.error("Error fetch_tag_and_release_date_helm_chart(versions): #{e.message}")
        versions
      end

      sig { params(repo_name: String).returns(T.nilable(T::Array[String])) }
      def select_tags_which_in_cooldown_from_chart(repo_name)
        version_tags_in_cooldown_from_chart = T.let([], T::Array[String])

        begin
          T.must(package_details_fetcher.fetch_tag_and_release_date_from_chart(repo_name)).each do |git_tag_with_detail|
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

      # To filter versions in cooldown period based on version tags from registry call
      sig { params(index_url: String, versions: T::Array[String]).returns(T::Array[String]) }
      def fetch_tag_and_release_date_helm_chart_index(index_url, versions)
        return versions unless cooldown_enabled?

        Dependabot.logger.info("Filtering versions in cooldown period from chart: #{index_url}")
        return versions unless select_tags_which_in_cooldown_from_chart_index(index_url).nil?

        # sort the allowed version tags by name in descending order
        select_tags_which_in_cooldown_from_chart_index(index_url)&.each do |tag_name|
          # Iterate through versions and filter out those matching the tag_name
          versions.reject! do |version|
            version == tag_name
          end
        end
        Dependabot.logger.info("Allowed version tags after filtering versions in cooldown:
              #{versions.map(&:to_s).join(', ')}")
        versions
      rescue StandardError => e
        Dependabot.logger.error("Error fetch_tag_and_release_date_helm_chart_index : #{e.message}")
        versions
      end

      sig { params(index_url: String).returns(T.nilable(T::Array[String])) }
      def select_tags_which_in_cooldown_from_chart_index(index_url)
        fetch_tag_and_release_date_helm_chart_index = T.let([], T::Array[String])

        begin
          package_details_fetcher.fetch_tag_and_release_date_helm_chart_index(index_url).each do |git_tag_with_detail|
            if check_if_version_in_cooldown_period?(T.must(git_tag_with_detail.release_date))
              fetch_tag_and_release_date_helm_chart_index << git_tag_with_detail.tag
            end
          end
          fetch_tag_and_release_date_helm_chart_index
        rescue StandardError => e
          Dependabot.logger.error("Error checking if version is in cooldown: #{e.message}")
          fetch_tag_and_release_date_helm_chart_index
        end
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

      sig { params(tags: T::Array[String], index_url: String).returns(T.nilable(T::Array[String])) }
      def select_tags_which_in_cooldown_using_oci(tags, index_url)
        fetch_tag_and_release_date_helm_using_oci = T.let([], T::Array[String])

        begin
          package_details_fetcher.fetch_tags_with_release_date_using_oci(tags, index_url)&.each do |git_tag_with_detail|
            if check_if_version_in_cooldown_period?(T.must(git_tag_with_detail.release_date))
              fetch_tag_and_release_date_helm_using_oci << git_tag_with_detail.tag
            end
          end
          fetch_tag_and_release_date_helm_using_oci
        rescue StandardError => e
          Dependabot.logger.error("Error checking if version is in cooldown: #{e.message}")
          fetch_tag_and_release_date_helm_using_oci
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
