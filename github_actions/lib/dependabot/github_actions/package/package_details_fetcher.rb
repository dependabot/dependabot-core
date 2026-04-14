# typed: strict
# frozen_string_literal: true

require "cgi"
require "json"
require "nokogiri"
require "sorbet-runtime"
require "time"

require "dependabot/errors"
require "dependabot/git_tag_with_detail"
require "dependabot/github_actions/helpers"
require "dependabot/github_actions/requirement"
require "dependabot/github_actions/update_checker"
require "dependabot/github_actions/version"
require "dependabot/package/package_details"
require "dependabot/package/package_release"
require "dependabot/registry_client"
require "dependabot/shared_helpers"
require "dependabot/source"

module Dependabot
  module GithubActions
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            raise_on_ignored: T::Boolean,
            security_advisories: T::Array[Dependabot::SecurityAdvisory]
          ).void
        end
        def initialize(
          dependency:,
          credentials:,
          ignored_versions: [],
          raise_on_ignored: false,
          security_advisories: []
        )
          @dependency = dependency
          @credentials = credentials
          @raise_on_ignored = raise_on_ignored
          @ignored_versions = ignored_versions
          @security_advisories = security_advisories

          @git_helper = T.let(git_helper, Dependabot::GithubActions::Helpers::Githelper)
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def release_list_for_git_dependency
          # TODO: Support Docker sources
          return unless git_dependency?
          return current_commit unless git_commit_checker.pinned?

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag.
          if git_commit_checker.pinned_ref_looks_like_version? && latest_version_tag
            latest_version = latest_version_tag&.fetch(:version)
            return current_version if shortened_semver_eq?(dependency.version, latest_version.to_s)

            return latest_version
          end

          if git_commit_checker.pinned_ref_looks_like_commit_sha? && latest_version_tag
            return latest_version_tag.fetch(:version)
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version or a commit SHA then there's nothing we can do.
          nil
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def lowest_security_fix_version_tag
          # TODO: Support Docker sources
          return unless git_dependency?

          @lowest_security_fix_version_tag ||= T.let(
            begin
              tags_matching_precision = git_commit_checker.local_tags_for_allowed_versions_matching_existing_precision
              lowest_fixed_version = find_lowest_secure_version(tags_matching_precision)
              if lowest_fixed_version
                lowest_fixed_version
              else
                tags = git_commit_checker.local_tags_for_allowed_versions
                find_lowest_secure_version(tags)
              end
            end,
            T.nilable(T::Hash[Symbol, String])
          )
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          @latest_version_tag ||= T.let(
            begin
              return git_commit_checker.local_tag_for_latest_version if dependency.version.nil?

              ref = git_commit_checker.local_ref_for_latest_version_matching_existing_precision
              return ref if ref && ref.fetch(:version) > current_version

              git_commit_checker.local_ref_for_latest_version_lower_precision
            end,
            T.nilable(T::Hash[Symbol, T.untyped])
          )
        end

        sig { returns(T::Array[Dependabot::GitTagWithDetail]) }
        def fetch_tag_and_release_date
          allowed_version_tags = git_commit_checker.allowed_version_tags
          allowed_tag_names = Set.new(allowed_version_tags.map(&:name))

          # Use the shared GitCommitChecker#refs_for_tag_with_detail to fetch all tags
          # with release dates in a single clone (instead of one clone per tag)
          all_refs_with_detail = git_commit_checker.refs_for_tag_with_detail

          result = all_refs_with_detail.select do |ref|
            allowed_tag_names.include?(ref.tag)
          end

          # Log an error if we couldn't fetch any release dates
          if result.empty? && allowed_version_tags.any?
            Dependabot.logger.error("Error fetching tag and release date: unable to fetch for allowed tags")
          end

          result
        rescue StandardError => e
          Dependabot.logger.error("Error fetching tag and release date: #{e.message}")
          []
        end

        sig do
          returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def allowed_version_tags_with_release_dates
          allowed_version_tags_hashes = git_commit_checker.local_tags_for_allowed_versions
          tag_to_release_date = T.let({}, T::Hash[String, T.nilable(String)])

          # Build a map of tag names to release dates for quick lookup
          fetch_tag_and_release_date.each do |git_tag_with_detail|
            tag_to_release_date[git_tag_with_detail.tag] = git_tag_with_detail.release_date
          end

          # Combine version info with release dates and sort by version descending
          result = allowed_version_tags_hashes.map do |tag_hash|
            tag_name = tag_hash.fetch(:tag)
            tag_hash.merge(
              release_date: tag_to_release_date[tag_name]
            )
          end

          # Sort by version descending (newest first)
          result.sort_by { |tag_hash| tag_hash.fetch(:version) }.reverse
        end

        private

        sig { returns(Dependabot::GitCommitChecker) }
        def git_commit_checker
          @git_commit_checker ||= T.let(
            @git_helper.git_commit_checker,
            T.nilable(Dependabot::GitCommitChecker)
          )
        end

        sig { returns(T.nilable(String)) }
        def current_commit
          git_commit_checker.head_commit_for_current_branch
        end

        sig { params(base: T.nilable(String), other: String).returns(T::Boolean) }
        def shortened_semver_eq?(base, other)
          return false unless base

          base_split = base.split(".")
          other_split = other.split(".")
          return false unless base_split.length <= other_split.length

          other_split[0..(base_split.length - 1)] == base_split
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def current_version
          @current_version ||= T.let(dependency.numeric_version, T.nilable(Dependabot::Version))
        end

        sig do
          params(tags: T::Array[T::Hash[Symbol, T.untyped]]).returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def find_lowest_secure_version(tags)
          relevant_tags = Dependabot::UpdateCheckers::VersionFilters
                          .filter_vulnerable_versions(tags, security_advisories)

          relevant_tags = filter_lower_tags(relevant_tags)
          relevant_tags.min_by { |tag| tag.fetch(:version) }
        end

        sig do
          params(tags_array: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def filter_lower_tags(tags_array)
          return tags_array unless current_version

          tags_array.select { |tag| tag.fetch(:version) > current_version }
        end

        sig { returns(T::Boolean) }
        def git_dependency?
          git_commit_checker.git_dependency?
        end

        sig { returns(Dependabot::GithubActions::Helpers::Githelper) }
        def git_helper
          Helpers::Githelper.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            consider_version_branches_pinned: false,
            dependency_source_details: nil
          )
        end
      end
    end
  end
end
