# typed: strict
# frozen_string_literal: true

require "cgi"
require "json"
require "nokogiri"
require "sorbet-runtime"
require "time"

require "dependabot/errors"
require "dependabot/github_actions/helpers"
require "dependabot/github_actions/requirement"
require "dependabot/github_actions/update_checker"
require "dependabot/github_actions/version"
require "dependabot/package/package_details"
require "dependabot/package/package_release"
require "dependabot/registry_client"
require "dependabot/shared_helpers"

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
        def initialize(dependency:,
                       credentials:,
                       ignored_versions: [],
                       raise_on_ignored: false,
                       security_advisories: [])
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
            latest_version = latest_version_tag&.fetch(:version)
            return latest_commit_for_pinned_ref unless git_commit_checker.local_tag_for_pinned_sha

            return latest_version
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

          other_split[0..base_split.length - 1] == base_split
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def current_version
          @current_version ||= T.let(dependency.numeric_version, T.nilable(Dependabot::Version))
        end

        sig { returns(T.nilable(String)) }
        def latest_commit_for_pinned_ref
          @latest_commit_for_pinned_ref ||= T.let(
            begin
              head_commit_for_ref_sha = git_commit_checker.head_commit_for_pinned_ref
              if head_commit_for_ref_sha
                head_commit_for_ref_sha
              else
                url = git_commit_checker.dependency_source_details&.fetch(:url)
                source = T.must(Source.from_url(url))

                SharedHelpers.in_a_temporary_directory(File.dirname(source.repo)) do |temp_dir|
                  repo_contents_path = File.join(temp_dir, File.basename(source.repo))

                  SharedHelpers.run_shell_command("git clone --no-recurse-submodules #{url} #{repo_contents_path}")

                  Dir.chdir(repo_contents_path) do
                    ref_branch = find_container_branch(git_commit_checker.dependency_source_details&.fetch(:ref))
                    git_commit_checker.head_commit_for_local_branch(ref_branch) if ref_branch
                  end
                end
              end
            end,
            T.nilable(String)
          )
        end

        sig { params(sha: String).returns(T.nilable(String)) }
        def find_container_branch(sha)
          branches_including_ref = SharedHelpers.run_shell_command(
            "git branch --remotes --contains #{sha}",
            fingerprint: "git branch --remotes --contains <sha>"
          ).split("\n").map { |branch| branch.strip.gsub("origin/", "") }
          return if branches_including_ref.empty?

          current_branch = branches_including_ref.find { |branch| branch.start_with?("HEAD -> ") }

          if current_branch
            current_branch.delete_prefix("HEAD -> ")
          elsif branches_including_ref.size > 1
            # If there are multiple non default branches including the pinned SHA,
            # then it's unclear how we should proceed
            raise "Multiple ambiguous branches (#{branches_including_ref.join(', ')}) include #{sha}!"
          else
            branches_including_ref.first
          end
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
          Helpers::Githelper.new(dependency: dependency, credentials: credentials,
                                 ignored_versions: ignored_versions, raise_on_ignored: raise_on_ignored,
                                 consider_version_branches_pinned: false, dependency_source_details: nil)
        end
      end
    end
  end
end
