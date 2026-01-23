# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/git_commit_checker"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/python/version"

module Dependabot
  module Python
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
          @git_commit_checker = git_commit_checker
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options

        sig { returns(Dependabot::GitCommitChecker) }
        attr_reader :git_commit_checker

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          return git_commit_checker.local_tag_for_latest_version unless cooldown_enabled?

          allowed_version_tags = git_commit_checker.local_tags_for_allowed_versions
          tags_in_cooldown = select_version_tags_in_cooldown_period

          return max_version_from_tags(allowed_version_tags) if tags_in_cooldown.empty?

          filtered_tags = allowed_version_tags.reject do |tag|
            tags_in_cooldown.include?(tag[:tag])
          end

          if filtered_tags.empty?
            Dependabot.logger.info("All git tags filtered by cooldown for #{dependency.name}, returning nil")
            return nil
          end

          filtered_count = allowed_version_tags.count - filtered_tags.count
          if filtered_count.positive?
            Dependabot.logger.info("Filtered #{filtered_count} git tags due to cooldown for #{dependency.name}")
          end

          max_version_from_tags(filtered_tags)
        rescue StandardError => e
          Dependabot.logger.error("Error fetching latest version tag: #{e.message}")
          git_commit_checker.local_tag_for_latest_version
        end

        private

        sig { params(tags: T::Array[T::Hash[Symbol, T.untyped]]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def max_version_from_tags(tags)
          tags.max_by { |t| t[:version] }
        end

        sig { returns(T::Array[String]) }
        def select_version_tags_in_cooldown_period
          version_tags_in_cooldown_period = T.let([], T::Array[String])

          git_commit_checker.refs_for_tag_with_detail.each do |git_tag_with_detail|
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
          tag_version_str = tag_with_detail.tag.delete_prefix("v")
          return false unless version_class.correct?(tag_version_str)

          new_version = version_class.new(tag_version_str)
          days = cooldown_days_for(current_version, new_version)

          passed_seconds = Time.now.to_i - release_date_to_seconds(tag_with_detail.release_date)
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

          return cooldown.default_days if current_version_semver.nil? || new_version_semver.nil?

          current_major, current_minor, current_patch = current_version_semver
          new_major, new_minor, new_patch = new_version_semver

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
          0
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
