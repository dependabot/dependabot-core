# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/github_actions/version"
require "dependabot/github_actions/requirement"

module Dependabot
  module GithubActions
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      attr_reader :docker_deps
      attr_reader :dependency
      def initialize(dependency:, dependency_files:, credentials:,
                     ignored_versions: [], raise_on_ignored: false,
                     security_advisories: [],
                     requirements_update_strategy: nil)
        if dependency.package_manager == "docker"
          @dependency = dependency
          @security_advisories = []
          @docker_deps = Docker::UpdateChecker.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            requirements_update_strategy: requirements_update_strategy,
            ignored_versions: ignored_versions,
            security_advisories: Dependabot::SecurityAdvisory.new(
              dependency_name: dependency.name,
              package_manager: "docker",
              vulnerable_versions: [],
              safe_versions: []
            )
          )
        else
          super
        end
      end

      def latest_version
        if dependency.package_manager == "docker"
          return docker_deps.latest_version
        end
        @latest_version ||= fetch_latest_version
      end

      def latest_resolvable_version
        if dependency.package_manager == "docker"
          return docker_deps.latest_resolvable_version
        end
        # Resolvability isn't an issue for GitHub Actions.
        latest_version
      end

      def latest_resolvable_version_with_no_unlock
        if dependency.package_manager == "docker"
          return docker_deps.latest_resolvable_version_with_no_unlock
        end
        # No concept of "unlocking" for GitHub Actions (since no lockfile)
        dependency.version
      end

      def updated_requirements
        if dependency.package_manager == "docker"
          return docker_deps.updated_requirements
        end
        if updated_source == dependency_source_details
          return dependency.requirements
        end

        dependency.requirements.map { |req| req.merge(source: updated_source) }
      end

      private

      def version_up_to_date?
        if dependency.package_manager == "docker"
          return docker_deps.send(:version_up_to_date?)
        end

        super
      end

      def version_can_update?(*)
        if dependency.package_manager == "docker"
          return !docker_deps.send(:version_up_to_date?)
        end

        super
      end

      def ignore_reqs
        if dependency.package_manager == "docker"
          return docker_deps.send(:ignore_reqs)
        end

        super
      end

      # # copied from base class
      # def vulnerable?
      #   return false if security_advisories.none?

      #   # Can't (currently) detect whether dependencies without a version
      #   # (i.e., for repos without a lockfile) are vulnerable
      #   return false unless dependency.version

      #   # Can't (currently) detect whether git dependencies are vulnerable
      #   return false if existing_version_is_sha?

      #   if dependency.package_manager == "docker"
      #     # dirty hack
      #     @security_advisories = []
      #   end
      #   version = version_class.new(dependency.version)
      #   security_advisories.any? { |a| a.vulnerable?(version) }
      # end

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
        unless git_commit_checker.pinned?
          return git_commit_checker.head_commit_for_current_branch
        end

        # If the dependency is pinned to a tag that looks like a version then
        # we want to update that tag. The latest version will then be the SHA
        # of the latest tag that looks like a version.
        if git_commit_checker.pinned_ref_looks_like_version? &&
           git_commit_checker.local_tag_for_latest_version
          latest_tag = git_commit_checker.local_tag_for_latest_version
          return latest_tag.fetch(:commit_sha)
        end

        # If the dependency is pinned to a commit SHA and the latest
        # version-like tag includes that commit then we want to update to that
        # version-like tag. We return a version (not a commit SHA) so that we
        # get nice behaviour in PullRequestCreator::MessageBuilder
        if git_commit_checker.pinned_ref_looks_like_commit_sha? &&
           (latest_tag = git_commit_checker.local_tag_for_latest_version) &&
           git_commit_checker.branch_or_ref_in_release?(latest_tag[:version])
          return latest_tag.fetch(:version)
        end

        # If the dependency is pinned to a tag that doesn't look like a
        # version or a commit SHA then there's nothing we can do.
        dependency.version
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def updated_source
        # TODO: Support Docker sources
        return dependency_source_details unless git_dependency?

        # Update the git tag if updating a pinned version
        if git_commit_checker.pinned_ref_looks_like_version? &&
           (new_tag = git_commit_checker.local_tag_for_latest_version) &&
           new_tag.fetch(:commit_sha) != current_commit
          return dependency_source_details.merge(ref: new_tag.fetch(:tag))
        end

        # Update the git tag if updating a pinned commit
        if git_commit_checker.pinned_ref_looks_like_commit_sha? &&
           (latest_tag = git_commit_checker.local_tag_for_latest_version) &&
           git_commit_checker.branch_or_ref_in_release?(latest_tag[:version])
          return dependency_source_details.merge(ref: latest_tag.fetch(:tag))
        end

        # Otherwise return the original source
        dependency_source_details
      end

      # rubocop:enable Metrics/PerceivedComplexity

      def dependency_source_details
        sources =
          dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

        return sources.first if sources.count <= 1

        # If there are multiple source types, or multiple source URLs, then it's
        # unclear how we should proceed
        if sources.map { |s| [s.fetch(:type), s[:url]] }.uniq.count > 1
          raise "Multiple sources! #{sources.join(', ')}"
        end

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
          raise_on_ignored: raise_on_ignored
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("github_actions", Dependabot::GithubActions::UpdateChecker)
