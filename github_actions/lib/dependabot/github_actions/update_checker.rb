# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/github_actions/requirement"
require "dependabot/github_actions/version"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module GithubActions
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(
          fetch_latest_version,
          T.nilable(T.any(String, Gem::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # Resolvability isn't an issue for GitHub Actions.
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        # No concept of "unlocking" for GitHub Actions (since no lockfile)
        dependency.version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        @lowest_security_fix_version ||= T.let(
          fetch_lowest_security_fix_version,
          T.nilable(Dependabot::Version)
        )
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        # Resolvability isn't an issue for GitHub Actions.
        lowest_security_fix_version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dependency.requirements.map do |req|
          source = req[:source]
          updated = updated_ref(source)
          next req unless updated

          current = source[:ref]

          # Maintain a short git hash only if it matches the latest
          if req[:type] == "git" &&
             git_commit_checker.ref_looks_like_commit_sha?(updated) &&
             git_commit_checker.ref_looks_like_commit_sha?(current) &&
             updated.start_with?(current)
            next req
          end

          new_source = source.merge(ref: updated)
          req.merge(source: new_source)
        end
      end

      private

      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      def active_advisories
        security_advisories.select do |advisory|
          version = git_commit_checker.most_specific_tag_equivalent_to_pinned_ref
          version.nil? ? false : advisory.vulnerable?(version_class.new(version))
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for GitHub Actions
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
      def fetch_latest_version
        # TODO: Support Docker sources
        return unless git_dependency?

        fetch_latest_version_for_git_dependency
      end

      sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
      def fetch_latest_version_for_git_dependency
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

      sig { returns(T.nilable(Dependabot::Version)) }
      def fetch_lowest_security_fix_version
        # TODO: Support Docker sources
        return unless git_dependency?

        fetch_lowest_security_fix_version_for_git_dependency
      end

      sig { returns(T.nilable(Dependabot::Version)) }
      def fetch_lowest_security_fix_version_for_git_dependency
        lowest_security_fix_version_tag&.fetch(:version)
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def lowest_security_fix_version_tag
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

      sig do
        params(
          tags: T::Array[T::Hash[Symbol, T.untyped]]
        )
          .returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def find_lowest_secure_version(tags)
        relevant_tags = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(tags, security_advisories)
        relevant_tags = filter_lower_tags(relevant_tags)

        relevant_tags.min_by { |tag| tag.fetch(:version) }
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

      sig do
        params(
          tags_array: T::Array[T::Hash[Symbol, T.untyped]]
        )
          .returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def filter_lower_tags(tags_array)
        return tags_array unless current_version

        tags_array
          .select { |tag| tag.fetch(:version) > current_version }
      end

      sig { params(source: T.nilable(T::Hash[Symbol, String])).returns(T.nilable(String)) }
      def updated_ref(source)
        # TODO: Support Docker sources
        return unless git_dependency?

        if vulnerable? &&
           (new_tag = lowest_security_fix_version_tag)
          return new_tag.fetch(:tag)
        end

        source_git_commit_checker = git_commit_checker_for(source)

        # Return the git tag if updating a pinned version
        if source_git_commit_checker.pinned_ref_looks_like_version? &&
           (new_tag = latest_version_tag)
          return new_tag.fetch(:tag)
        end

        # Return the pinned git commit if one is available
        if source_git_commit_checker.pinned_ref_looks_like_commit_sha? &&
           (new_commit_sha = latest_commit_sha)
          return new_commit_sha
        end

        # Otherwise we can't update the ref
        nil
      end

      sig { returns(T.nilable(String)) }
      def latest_commit_sha
        new_tag = latest_version_tag
        return unless new_tag

        if git_commit_checker.local_tag_for_pinned_sha
          new_tag.fetch(:commit_sha)
        else
          latest_commit_for_pinned_ref
        end
      end

      sig { returns(T.nilable(String)) }
      def current_commit
        git_commit_checker.head_commit_for_current_branch
      end

      sig { returns(T::Boolean) }
      def git_dependency?
        git_commit_checker.git_dependency?
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(
          git_commit_checker_for(nil),
          T.nilable(Dependabot::GitCommitChecker)
        )
      end

      sig { params(source: T.nilable(T::Hash[Symbol, String])).returns(Dependabot::GitCommitChecker) }
      def git_commit_checker_for(source)
        @git_commit_checkers ||= T.let(
          {},
          T.nilable(T::Hash[T.nilable(T::Hash[Symbol, String]), Dependabot::GitCommitChecker])
        )

        @git_commit_checkers[source] ||= Dependabot::GitCommitChecker.new(
          dependency: dependency,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          consider_version_branches_pinned: true,
          dependency_source_details: source
        )
      end

      sig { params(base: T.nilable(String), other: String).returns(T::Boolean) }
      def shortened_semver_eq?(base, other)
        return false unless base

        base_split = base.split(".")
        other_split = other.split(".")
        return false unless base_split.length <= other_split.length

        other_split[0..base_split.length - 1] == base_split
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
          # If there are multiple non default branches including the pinned SHA, then it's unclear how we should proceed
          raise "Multiple ambiguous branches (#{branches_including_ref.join(', ')}) include #{sha}!"
        else
          branches_including_ref.first
        end
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("github_actions", Dependabot::GithubActions::UpdateChecker)
