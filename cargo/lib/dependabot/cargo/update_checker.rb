# frozen_string_literal: true

require "dependabot/git_commit_checker"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Cargo
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"
      require_relative "update_checker/file_preparer"

      def latest_version
        return if path_dependency?

        @latest_version =
          if git_dependency?
            latest_version_for_git_dependency
          elsif git_subdependency?
            # TODO: Dependabot can't update git sub-dependencies yet, because
            # they can't be passed to GitCommitChecker.
            nil
          else
            latest_version_finder.latest_version
          end
      end

      def latest_resolvable_version
        return if path_dependency?

        @latest_resolvable_version ||=
          if git_dependency?
            latest_resolvable_version_for_git_dependency
          elsif git_subdependency?
            # TODO: Dependabot can't update git sub-dependencies yet, because
            # they can't be passed to GitCommitChecker.
            nil
          else
            fetch_latest_resolvable_version(unlock_requirement: true)
          end
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
        return if path_dependency?

        @latest_resolvable_version_with_no_unlock ||=
          if git_dependency?
            latest_resolvable_commit_with_unchanged_git_source
          else
            fetch_latest_resolvable_version(unlock_requirement: false)
          end
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          updated_source: updated_source,
          target_version: target_version,
          update_strategy: requirements_update_strategy
        ).updated_requirements
      end

      def requirements_unlocked_or_can_be?
        requirements_update_strategy != :lockfile_only
      end

      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        return @requirements_update_strategy.to_sym if @requirements_update_strategy

        # Otherwise, widen ranges for libraries and bump versions for apps
        library? ? :bump_versions_if_necessary : :bump_versions
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Rust (yet)
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def target_version
        # Unless we can resolve a new version, don't try to update to a latest
        # version (even for a library) as we rely on a resolvable version being
        # present in other areas
        return unless preferred_resolvable_version

        library? ? latest_version&.to_s : preferred_resolvable_version.to_s
      end

      def library?
        # If it has a lockfile, treat it as an application. Otherwise treat it
        # as a library.
        dependency_files.none? { |f| f.name == "Cargo.lock" }
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

      def latest_version_for_git_dependency
        latest_git_version_sha
      end

      def latest_git_version_sha
        # If the gem isn't pinned, the latest version is just the latest
        # commit for the specified branch.
        return git_commit_checker.head_commit_for_current_branch unless git_commit_checker.pinned?

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

      def latest_resolvable_version_for_git_dependency
        # If the gem isn't pinned, the latest version is just the latest
        # commit for the specified branch.
        return latest_resolvable_commit_with_unchanged_git_source unless git_commit_checker.pinned?

        # If the dependency is pinned to a tag that looks like a version then
        # we want to update that tag. The latest version will then be the SHA
        # of the latest tag that looks like a version.
        if git_commit_checker.pinned_ref_looks_like_version? &&
           latest_git_tag_is_resolvable?
          new_tag = git_commit_checker.local_tag_for_latest_version
          return new_tag.fetch(:commit_sha)
        end

        # If the dependency is pinned then there's nothing we can do.
        dependency.version
      end

      def latest_git_tag_is_resolvable?
        return @git_tag_resolvable if @latest_git_tag_is_resolvable_checked

        @latest_git_tag_is_resolvable_checked = true

        return false if git_commit_checker.local_tag_for_latest_version.nil?

        replacement_tag = git_commit_checker.local_tag_for_latest_version

        prepared_files = FilePreparer.new(
          dependency_files: dependency_files,
          dependency: dependency,
          unlock_requirement: true,
          replacement_git_pin: replacement_tag.fetch(:tag)
        ).prepared_dependency_files

        VersionResolver.new(
          dependency: dependency,
          prepared_dependency_files: prepared_files,
          original_dependency_files: dependency_files,
          credentials: credentials
        ).latest_resolvable_version
        @git_tag_resolvable = true
      rescue SharedHelpers::HelperSubprocessFailed => e
        raise e unless e.message.include?("versions conflict")

        @git_tag_resolvable = false
      end

      def latest_resolvable_commit_with_unchanged_git_source
        fetch_latest_resolvable_version(unlock_requirement: false)
      rescue SharedHelpers::HelperSubprocessFailed => e
        # Resolution may fail, as Cargo updates straight to the tip of the
        # branch. Just return `nil` if it does (so no update).
        return if e.message.include?("versions conflict")

        raise e
      end

      def fetch_latest_resolvable_version(unlock_requirement:)
        prepared_files = FilePreparer.new(
          dependency_files: dependency_files,
          dependency: dependency,
          unlock_requirement: unlock_requirement,
          latest_allowable_version: latest_version
        ).prepared_dependency_files

        VersionResolver.new(
          dependency: dependency,
          prepared_dependency_files: prepared_files,
          original_dependency_files: dependency_files,
          credentials: credentials
        ).latest_resolvable_version
      end

      def fetch_lowest_resolvable_security_fix_version
        fix_version = lowest_security_fix_version
        return latest_resolvable_version if fix_version.nil?

        return latest_resolvable_version if path_dependency? || git_dependency? || git_subdependency?

        prepared_files = FilePreparer.new(
          dependency_files: dependency_files,
          dependency: dependency,
          unlock_requirement: true,
          latest_allowable_version: fix_version
        ).prepared_dependency_files

        resolved_fix_version = VersionResolver.new(
          dependency: dependency,
          prepared_dependency_files: prepared_files,
          original_dependency_files: dependency_files,
          credentials: credentials
        ).latest_resolvable_version

        return fix_version if fix_version == resolved_fix_version

        latest_resolvable_version
      end

      def updated_source
        # Never need to update source, unless a git_dependency
        return dependency_source_details unless git_dependency?

        # Update the git tag if updating a pinned version
        if git_commit_checker.pinned_ref_looks_like_version? &&
           latest_git_tag_is_resolvable?
          new_tag = git_commit_checker.local_tag_for_latest_version
          return dependency_source_details.merge(ref: new_tag.fetch(:tag))
        end

        # Otherwise return the original source
        dependency_source_details
      end

      def dependency_source_details
        dependency.source_details
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def git_subdependency?
        return false if dependency.top_level?

        !version_class.correct?(dependency.version)
      end

      def path_dependency?
        dependency.source_details&.fetch(:type) == "path"
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

Dependabot::UpdateCheckers.register("cargo", Dependabot::Cargo::UpdateChecker)
