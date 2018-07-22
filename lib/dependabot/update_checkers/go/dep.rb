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
              fetch_latest_resolvable_version(unlock_requirement: true)
            end
        end

        def latest_resolvable_version_with_no_unlock
          @latest_resolvable_version_with_no_unlock ||=
            if git_dependency?
              latest_resolvable_commit_with_unchanged_git_source
            else
              fetch_latest_resolvable_version(unlock_requirement: false)
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
          # TODO
        end

        def latest_resolvable_commit_with_unchanged_git_source
          # TODO
        end

        def fetch_latest_resolvable_version(unlock_requirement:)
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

        def git_dependency?
          git_commit_checker.git_dependency?
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
end
