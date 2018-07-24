# frozen_string_literal: true

require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Go
      class Dep < Dependabot::UpdateCheckers::Base
        require_relative "dep/file_preparer"
        require_relative "dep/latest_version_finder"
        require_relative "dep/version_resolver"

        def latest_version
          @latest_version ||=
            LatestVersionFinder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              ignored_versions: ignored_versions
            ).latest_version
        end

        def latest_resolvable_version
          @latest_resolvable_version ||=
            if git_dependency?
              latest_resolvable_version_for_git_dependency
            else
              latest_resolvable_released_version(unlock_requirement: true)
            end
        end

        def latest_resolvable_version_with_no_unlock
          @latest_resolvable_version_with_no_unlock ||=
            if git_dependency?
              latest_resolvable_commit_with_unchanged_git_source
            else
              latest_resolvable_released_version(unlock_requirement: false)
            end
        end

        def updated_requirements
          # If the dependency file needs to be updated we store the updated
          # requirements on the dependency.
          #
          # TODO!
          dependency.requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Go (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def latest_resolvable_version_for_git_dependency
          latest_release =
            latest_resolvable_released_version(unlock_requirement: true)

          # If there's a resolvable release that includes the current pinned
          # ref or that the current branch is behind, we switch to that release.
          return latest_release if git_branch_or_ref_in_release?(latest_release)

          # Otherwise, if the gem isn't pinned, the latest version is just the
          # latest commit for the specified branch.
          unless git_commit_checker.pinned?
            return latest_resolvable_commit_with_unchanged_git_source
          end

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag. The latest version will be the
          # tag name (NOT the tag SHA, unlike in other package managers).
          if git_commit_checker.pinned_ref_looks_like_version? &&
             latest_git_tag_is_resolvable?
            new_tag = git_commit_checker.local_tag_for_latest_version
            return new_tag.fetch(:tag)
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          nil
        end

        def latest_resolvable_commit_with_unchanged_git_source
          @latest_resolvable_commit_with_unchanged_git_source ||=
            begin
              prepared_files = FilePreparer.new(
                dependency_files: dependency_files,
                dependency: dependency,
                unlock_requirement: false,
                remove_git_source: false,
                latest_allowable_version: latest_version
              ).prepared_dependency_files

              VersionResolver.new(
                dependency: dependency,
                dependency_files: prepared_files,
                credentials: credentials
              ).latest_resolvable_version
            end
        end

        def latest_resolvable_released_version(unlock_requirement:)
          @latest_resolvable_released_version ||= {}
          @latest_resolvable_released_version[unlock_requirement] ||=
            begin
              prepared_files = FilePreparer.new(
                dependency_files: dependency_files,
                dependency: dependency,
                unlock_requirement: unlock_requirement,
                remove_git_source: git_dependency?,
                latest_allowable_version: latest_version
              ).prepared_dependency_files

              VersionResolver.new(
                dependency: dependency,
                dependency_files: prepared_files,
                credentials: credentials
              ).latest_resolvable_version
            end
        end

        def latest_git_tag_is_resolvable?
          return @git_tag_resolvable if @latest_git_tag_is_resolvable_checked
          @latest_git_tag_is_resolvable_checked = true

          return false if git_commit_checker.local_tag_for_latest_version.nil?
          replacement_tag = git_commit_checker.local_tag_for_latest_version

          prepared_files = FilePreparer.new(
            dependency: dependency,
            dependency_files: dependency_files,
            unlock_requirement: false,
            remove_git_source: false,
            replacement_git_pin: replacement_tag.fetch(:tag)
          ).prepared_dependency_files

          VersionResolver.new(
            dependency: dependency,
            dependency_files: prepared_files,
            credentials: credentials
          ).latest_resolvable_version

          @git_tag_resolvable = true
        rescue Dependabot::DependencyFileNotResolvable
          @git_tag_resolvable = false
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def git_branch_or_ref_in_release?(release)
          return false unless release
          git_commit_checker.branch_or_ref_in_release?(release)
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              credentials: credentials,
              ignored_versions: ignored_versions
            )
        end
      end
    end
  end
end
