# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/puppet/requirement"

module Dependabot
  module Puppet
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/latest_version_finder"

      def latest_version
        @latest_version ||=
          if git_dependency?
            latest_version_for_git_dependency
          else
            latest_version_finder.latest_version
          end
      end

      def latest_resolvable_version
        latest_version
      end

      def latest_resolvable_version_with_no_unlock
        @latest_resolvable_version_with_no_unlock ||=
          latest_version_finder.
          latest_version_with_no_unlock
      end

      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        if defined?(@lowest_resolvable_security_fix_version)
          return @lowest_resolvable_security_fix_version
        end

        @lowest_resolvable_security_fix_version =
          latest_version_finder.
          lowest_security_fix_version
      end

      def updated_requirements
        return dependency.requirements unless latest_version

        dependency.requirements.map do |req|
          if git_dependency?
            req.merge(source: updated_source)
          else
            req.merge(requirement: latest_version&.to_s)
          end
        end
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Multi-dependency updates not supported
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def latest_version_for_git_dependency
        latest_git_version_sha
      end

      def latest_git_version_sha
        # If the gem isn't pinned, the latest version is just the latest
        # commit for the specified branch.
        unless git_commit_checker.pinned?
          return git_commit_checker.head_commit_for_current_branch
        end

        # If the dependency is pinned to a tag that looks like a version then
        # we want to update that tag. The latest version will then be the SHA
        # of the latest tag that looks like a version.
        if git_commit_checker.pinned_ref_looks_like_version?
          latest_tag = git_commit_checker.local_tag_for_latest_version
          return latest_tag&.fetch(:commit_sha) || dependency.version
        end

        # If the dependency is pinned to a tag that doesn't look like a
        # version then there's nothing we can do.
        dependency.version
      end

      def updated_source
        # Never need to update source, unless a git_dependency
        return dependency_source_details unless git_dependency?

        # Update the git tag if updating a pinned version
        if git_commit_checker.pinned_ref_looks_like_version? &&
           git_commit_checker.local_tag_for_latest_version
          new_tag = git_commit_checker.local_tag_for_latest_version
          return dependency_source_details.merge(ref: new_tag.fetch(:tag))
        end

        # Otherwise return the original source
        dependency_source_details
      end

      def dependency_source_details
        sources =
          dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

        raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

        sources.first
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def latest_version_finder
        @latest_version_finder ||= LatestVersionFinder.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: security_advisories
        )
      end

      def git_commit_checker
        @git_commit_checker ||=
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("puppet", Dependabot::Puppet::UpdateChecker)
