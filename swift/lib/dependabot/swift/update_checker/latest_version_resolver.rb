# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/update_checkers/cooldown_calculation"
require "dependabot/swift/package/package_details_fetcher"
require "sorbet-runtime"
require "dependabot/git_commit_checker"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionResolver
        extend T::Sig

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

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          return git_commit_checker.local_tag_for_latest_version if skip_cooldown?

          allowed_version_tags = git_commit_checker.allowed_version_tags
          select_version_tags_in_cooldown_period&.each do |tag_name|
            allowed_version_tags.reject! do |gitref_filtered|
              gitref_filtered.name == tag_name
            end
          end

          git_commit_checker.max_local_tag(allowed_version_tags)
        rescue Octokit::Error, ArgumentError => e
          Dependabot.logger.debug("Error fetching latest version tag: #{e.message}")
          git_commit_checker.local_tag_for_latest_version
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options

        sig { returns(Dependabot::GitCommitChecker) }
        attr_reader :git_commit_checker

        sig { returns(T.nilable(T::Array[String])) }
        def select_version_tags_in_cooldown_period
          version_tags_in_cooldown_period = T.let([], T::Array[String])

          package_details_fetcher.fetch_tag_and_release_date.each do |git_tag_with_detail|
            version_tags_in_cooldown_period << git_tag_with_detail.tag if version_in_cooldown?(git_tag_with_detail)
          end
          version_tags_in_cooldown_period
        rescue Octokit::Error, ArgumentError => e
          Dependabot.logger.debug("Error checking if version is in cooldown: #{e.message}")
          version_tags_in_cooldown_period
        end

        sig { params(tag_with_detail: Dependabot::GitTagWithDetail).returns(T::Boolean) }
        def version_in_cooldown?(tag_with_detail)
          return false unless tag_with_detail.release_date

          normalized_tag = tag_with_detail.tag.delete_prefix("v")
          return false unless version_class.correct?(normalized_tag)

          dep_version = dependency.version&.delete_prefix("v")
          current_version = dep_version && version_class.correct?(dep_version) ? version_class.new(dep_version) : nil
          new_version = version_class.new(normalized_tag)
          days = Dependabot::UpdateCheckers::CooldownCalculation.cooldown_days_for(
            T.must(cooldown_options), current_version, new_version
          )

          release_time = Time.parse(T.must(tag_with_detail.release_date))
          Dependabot::UpdateCheckers::CooldownCalculation.within_cooldown_window?(release_time, days)
        rescue ArgumentError => e
          Dependabot.logger.debug("Invalid release date format: #{tag_with_detail.release_date}, error: #{e.message}")
          false
        end

        sig { returns(T::Boolean) }
        def skip_cooldown?
          return true if cooldown_options.nil?

          cooldown = T.must(cooldown_options)
          has_positive_days = cooldown.default_days.to_i.positive? ||
                              cooldown.semver_major_days.to_i.positive? ||
                              cooldown.semver_minor_days.to_i.positive? ||
                              cooldown.semver_patch_days.to_i.positive?

          Dependabot::UpdateCheckers::CooldownCalculation.skip_cooldown?(
            cooldown_options, dependency.name, cooldown_enabled: has_positive_days
          )
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(Package::PackageDetailsFetcher) }
        def package_details_fetcher
          @package_details_fetcher ||= T.let(
            Package::PackageDetailsFetcher.new(
              dependency: dependency,
              credentials: credentials
            ),
            T.nilable(Package::PackageDetailsFetcher)
          )
        end
      end
    end
  end
end
