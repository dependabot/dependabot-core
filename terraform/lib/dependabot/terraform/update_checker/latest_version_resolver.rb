# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/terraform/package/package_details_fetcher"
require "sorbet-runtime"
require "dependabot/git_commit_checker"
require "dependabot/update_checkers/tag_cooldown_filter"

module Dependabot
  module Terraform
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionResolver
        extend T::Sig
        include Dependabot::UpdateCheckers::TagCooldownFilter

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
          @git_commit_checker = git_commit_checker
        end

        sig { override.returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { override.returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options

        # To filter versions in cooldown period based on version tags from registry call
        sig do
          params(versions: T::Array[Dependabot::Terraform::Version])
            .returns(T::Array[Dependabot::Terraform::Version])
        end
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
          Dependabot.logger.info(
            "Allowed version tags after filtering versions in cooldown:
                #{versions.join(', ')}"
          )
          versions
        rescue StandardError => e
          Dependabot.logger.error("Error filter_versions_in_cooldown_period_from_provider(versions): #{e.message}")
          versions
        end

        # To filter versions in cooldown period based on version tags from registry call
        sig do
          params(versions: T::Array[Dependabot::Terraform::Version])
            .returns(T::Array[Dependabot::Terraform::Version])
        end
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
          Dependabot.logger.info(
            "filter_versions_in_cooldown_period_from_module::
              Allowed version tags after filtering versions in cooldown:#{versions.join(', ')}"
          )
          versions
        rescue StandardError => e
          Dependabot.logger.error("Error fetching latest version tag: #{e.message}")
          versions
        end

        sig { returns(T.nilable(T::Array[String])) }
        def select_tags_which_in_cooldown_from_provider
          version_tags_in_cooldown_from_provider = T.let([], T::Array[String])

          package_details_fetcher.fetch_tag_and_release_date_from_provider.each do |git_tag_with_detail|
            if check_if_version_in_cooldown_period?(git_tag_with_detail.release_date)
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
            if check_if_version_in_cooldown_period?(git_tag_with_detail.release_date)
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
            ),
            T.nilable(Package::PackageDetailsFetcher)
          )
        end

        sig { returns(Dependabot::GitCommitChecker) }
        attr_reader :git_commit_checker

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
      end
    end
  end
end
