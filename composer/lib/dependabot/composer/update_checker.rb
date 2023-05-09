# frozen_string_literal: true

require "json"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Composer
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"
      require_relative "update_checker/latest_version_finder"

      def latest_version
        return nil if path_dependency?
        return latest_version_for_git_dependency if git_dependency?

        # Fall back to latest_resolvable_version if no listings found
        latest_version_from_registry || latest_resolvable_version
      end

      def latest_resolvable_version
        return nil if path_dependency? || git_dependency?

        @latest_resolvable_version ||=
          VersionResolver.new(
            credentials: credentials,
            dependency: dependency,
            dependency_files: dependency_files,
            latest_allowable_version: latest_version_from_registry,
            requirements_to_unlock: :own
          ).latest_resolvable_version
      end

      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
      end

      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        return @lowest_resolvable_security_fix_version if defined?(@lowest_resolvable_security_fix_version)

        @lowest_resolvable_security_fix_version =
          fetch_lowest_resolvable_security_fix_version
      end

      def latest_resolvable_version_with_no_unlock
        return nil if path_dependency? || git_dependency?

        @latest_resolvable_version_with_no_unlock ||=
          VersionResolver.new(
            credentials: credentials,
            dependency: dependency,
            dependency_files: dependency_files,
            latest_allowable_version: latest_version_from_registry,
            requirements_to_unlock: :none
          ).latest_resolvable_version
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_resolvable_version: preferred_resolvable_version&.to_s,
          update_strategy: requirements_update_strategy
        ).updated_requirements
      end

      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        return @requirements_update_strategy.to_sym if @requirements_update_strategy

        # Otherwise, widen ranges for libraries and bump versions for apps
        library? ? :widen_ranges : :bump_versions_if_necessary
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Composer (yet)
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def latest_version_from_registry
        latest_version_finder.latest_version
      end

      def latest_version_finder
        @latest_version_finder ||= LatestVersionFinder.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          security_advisories: security_advisories
        )
      end

      def fetch_lowest_resolvable_security_fix_version
        return nil if path_dependency? || git_dependency?

        fix_version = lowest_security_fix_version
        return latest_resolvable_version if fix_version.nil?

        resolved_fix_version = VersionResolver.new(
          credentials: credentials,
          dependency: dependency,
          dependency_files: dependency_files,
          latest_allowable_version: fix_version,
          requirements_to_unlock: :own
        ).latest_resolvable_version

        return fix_version if fix_version == resolved_fix_version

        latest_resolvable_version
      end

      def path_dependency?
        dependency.requirements.any? { |r| r.dig(:source, :type) == "path" }
      end

      # To be a true git dependency, it must have a branch.
      def git_dependency?
        dependency.requirements.any? { |r| r.dig(:source, :branch) }
      end

      def composer_file
        composer_file =
          dependency_files.find { |f| f.name == "composer.json" }
        raise "No composer.json!" unless composer_file

        composer_file
      end

      def library?
        JSON.parse(composer_file.content)["type"] == "library"
      end

      def latest_version_for_git_dependency
        # If the dependency isn't pinned then we just want to check that it
        # points to the latest commit on the relevant branch.
        return git_commit_checker.head_commit_for_current_branch unless git_commit_checker.pinned?

        # If the dependency is pinned to a tag that looks like a version then
        # we want to update that tag. The latest version will then be the SHA
        # of the latest tag that looks like a version.
        if git_commit_checker.pinned_ref_looks_like_version? &&
           git_commit_checker.local_tag_for_latest_version
          latest_tag = git_commit_checker.local_tag_for_latest_version
          return latest_tag.fetch(:commit_sha)
        end

        # If the dependency is pinned to a tag that doesn't look like a
        # version then there's nothing we can do.
        dependency.version
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
  register("composer", Dependabot::Composer::UpdateChecker)
