# typed: strict
# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/git_commit_checker"
require "dependabot/python/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"
require "dependabot/python/package/package_registry_finder"
require "dependabot/python/package/package_details_fetcher"
require "dependabot/package/package_latest_version_finder"

module Dependabot
  module Python
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          params(git_commit_checker: Dependabot::GitCommitChecker)
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def latest_version_tag(git_commit_checker:)
          return git_commit_checker.local_tag_for_latest_version unless cooldown_enabled?

          allowed_version_tags = git_commit_checker.local_tags_for_allowed_versions
          tags_in_cooldown = select_version_tags_in_cooldown_period(git_commit_checker)

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

        sig do
          override.returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def package_details
          @package_details ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          ).fetch
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          return false if cooldown_options.nil?

          cooldown = T.must(cooldown_options)
          cooldown.default_days.to_i.positive? ||
            cooldown.semver_major_days.to_i.positive? ||
            cooldown.semver_minor_days.to_i.positive? ||
            cooldown.semver_patch_days.to_i.positive?
        end

        private

        sig { params(tags: T::Array[T::Hash[Symbol, T.untyped]]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def max_version_from_tags(tags)
          tags.max_by { |t| t[:version] }
        end

        sig { params(git_commit_checker: Dependabot::GitCommitChecker).returns(T::Array[String]) }
        def select_version_tags_in_cooldown_period(git_commit_checker)
          version_tags_in_cooldown_period = T.let([], T::Array[String])

          git_commit_checker.refs_for_tag_with_detail.each do |git_tag_with_detail|
            if check_if_version_in_cooldown_period?(git_tag_with_detail)
              version_tags_in_cooldown_period << git_tag_with_detail.tag
            end
          end
          version_tags_in_cooldown_period
        rescue StandardError => e
          Dependabot.logger.error("Error checking if version is in cooldown: #{e.message}")
          []
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

        private

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_latest_versions_filter(releases)
          # Filter based on UPPER BOUND constraints only (<, <=, !=)
          # We want to find the latest version that doesn't exceed upper limits
          # Lower bounds (>, >=) should NOT restrict - we want newer versions above lower bounds
          # Pinning constraints (==, ~=, ^) are the target of updates and should be ignored
          return releases if dependency.requirements.empty?

          reqs = extract_upper_bound_requirements
          return releases if reqs.empty?

          releases.select { |release| reqs.all? { |req| req.satisfied_by?(release.version) } }
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def extract_upper_bound_requirements
          T.let(
            dependency.requirements.filter_map do |r|
              requirement_value = r.fetch(:requirement, nil)
              # Skip if nil or not a String
              next unless requirement_value.is_a?(String)

              # Type guard above ensures requirement_value is a String
              requirement_string = T.let(requirement_value, String)
              upper_bound_parts = extract_upper_bound_parts(requirement_string)
              next if upper_bound_parts.empty?

              # Join upper bound parts and create a single requirement
              upper_bound_requirement_string = upper_bound_parts.join(",")
              requirement_class.new(upper_bound_requirement_string)
            end.compact,
            T::Array[Dependabot::Requirement]
          )
        end

        sig { params(requirement_string: String).returns(T::Array[String]) }
        def extract_upper_bound_parts(requirement_string)
          # Only extract UPPER BOUND constraints: <, <=, !=
          # NOT lower bounds (>, >=) - we want to find newer versions above lower bounds
          T.let(
            requirement_string.split(",").map(&:strip).select do |part|
              # Match < or <= (but not <=>) or != followed by version
              part.match?(/^\s*(<(?!=)|<=|!=)\s*\d/)
            end,
            T::Array[String]
          )
        end
      end
    end
  end
end
