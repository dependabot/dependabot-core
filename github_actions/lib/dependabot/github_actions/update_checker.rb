# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/github_actions/version"
require "dependabot/github_actions/requirement"

module Dependabot
  module GithubActions
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def latest_version
        @latest_version ||= fetch_latest_version
      end

      def latest_resolvable_version
        # Resolvability isn't an issue for GitHub Actions.
        latest_version
      end

      def latest_resolvable_version_with_no_unlock
        # No concept of "unlocking" for GitHub Actions (since no lockfile)
        dependency.version
      end

      def updated_requirements # rubocop:disable Metrics/PerceivedComplexity
        previous = dependency_source_details
        updated = updated_source
        return dependency.requirements if updated == previous

        # Maintain a short git hash only if it matches the latest
        if previous[:type] == "git" &&
           previous[:url] == updated[:url] &&
           updated[:ref]&.match?(/^[0-9a-f]{6,40}$/) &&
           previous[:ref]&.match?(/^[0-9a-f]{6,40}$/) &&
           updated[:ref]&.start_with?(previous[:ref])
          return dependency.requirements
        end

        dependency.requirements.map { |req| req.merge(source: updated) }
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for GitHub Actions
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def fetch_latest_version
        # TODO: Support Docker sources
        return unless git_dependency?

        fetch_latest_version_for_git_dependency
      end

      def fetch_latest_version_for_git_dependency
        return current_commit unless git_commit_checker.pinned?

        # If the dependency is pinned to a tag that looks like a version then
        # we want to update that tag.
        if git_commit_checker.pinned_ref_looks_like_version? && latest_version_tag
          latest_version = latest_version_tag.fetch(:version)
          return version_class.new(dependency.version) if shortened_semver_eq?(dependency.version, latest_version.to_s)

          return latest_version
        end

        if git_commit_checker.pinned_ref_looks_like_commit_sha? && latest_version_tag
          latest_version = latest_version_tag.fetch(:version)
          return latest_commit_for_pinned_ref unless git_commit_checker.branch_or_ref_in_release?(latest_version)

          return latest_version
        end

        # If the dependency is pinned to a tag that doesn't look like a
        # version or a commit SHA then there's nothing we can do.
        nil
      end

      def latest_commit_for_pinned_ref
        @latest_commit_for_pinned_ref ||= begin
          head_commit_for_ref_sha = git_commit_checker.head_commit_for_pinned_ref
          if head_commit_for_ref_sha
            head_commit_for_ref_sha
          else
            url = dependency_source_details[:url]
            source = Source.from_url(url)

            SharedHelpers.in_a_temporary_directory(File.dirname(source.repo)) do |temp_dir|
              repo_contents_path = File.join(temp_dir, File.basename(source.repo))

              SharedHelpers.run_shell_command("git clone --no-recurse-submodules #{url} #{repo_contents_path}")

              Dir.chdir(repo_contents_path) do
                ref_branch = find_container_branch(dependency_source_details[:ref])

                git_commit_checker.head_commit_for_local_branch(ref_branch)
              end
            end
          end
        end
      end

      def latest_version_tag
        @latest_version_tag ||= begin
          return git_commit_checker.local_tag_for_latest_version if dependency.version.nil?

          git_commit_checker.local_ref_for_latest_version_matching_existing_precision
        end
      end

      def updated_source
        # TODO: Support Docker sources
        return dependency_source_details unless git_dependency?

        # Update the git tag if updating a pinned version
        if git_commit_checker.pinned_ref_looks_like_version? &&
           (new_tag = latest_version_tag) &&
           new_tag.fetch(:commit_sha) != current_commit
          return dependency_source_details.merge(ref: new_tag.fetch(:tag))
        end

        # Update the pinned git commit if one is available
        if git_commit_checker.pinned_ref_looks_like_commit_sha? &&
           (new_commit_sha = latest_commit_sha) &&
           new_commit_sha != current_commit
          return dependency_source_details.merge(ref: new_commit_sha)
        end

        # Otherwise return the original source
        dependency_source_details
      end

      def latest_commit_sha
        new_tag = latest_version_tag
        return unless new_tag

        if git_commit_checker.branch_or_ref_in_release?(new_tag.fetch(:version))
          new_tag.fetch(:commit_sha)
        else
          latest_commit_for_pinned_ref
        end
      end

      def dependency_source_details
        sources =
          dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

        return sources.first if sources.count <= 1

        # If there are multiple source types, or multiple source URLs, then it's
        # unclear how we should proceed
        raise "Multiple sources! #{sources.join(', ')}" if sources.map { |s| [s.fetch(:type), s[:url]] }.uniq.count > 1

        # Otherwise it's reasonable to take the first source and use that. This
        # will happen if we have multiple git sources with difference references
        # specified. In that case it's fine to update them all.
        sources.first
      end

      def current_commit
        git_commit_checker.head_commit_for_current_branch
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def git_commit_checker
        @git_commit_checker ||= Dependabot::GitCommitChecker.new(
          dependency: dependency,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          consider_version_branches_pinned: true
        )
      end

      def shortened_semver_eq?(base, other)
        return false unless base

        base_split = base.split(".")
        other_split = other.split(".")
        return false unless base_split.length <= other_split.length

        other_split[0..base_split.length - 1] == base_split
      end

      def find_container_branch(sha)
        branches_including_ref = SharedHelpers.run_shell_command(
          "git branch --remotes --contains #{sha}"
        ).split("\n").map { |branch| branch.strip.gsub("origin/", "") }

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

Dependabot::UpdateCheckers.
  register("github_actions", Dependabot::GithubActions::UpdateChecker)
