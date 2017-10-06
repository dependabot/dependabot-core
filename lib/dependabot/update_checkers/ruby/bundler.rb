# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler < Dependabot::UpdateCheckers::Base
        require_relative "bundler/file_preparer"
        require_relative "bundler/requirements_updater"
        require_relative "bundler/version_resolver"

        def latest_version
          return latest_version_for_git_dependency if git_dependency?
          latest_version_details&.fetch(:version)
        end

        def latest_resolvable_version
          return latest_resolvable_version_for_git_dependency if git_dependency?
          latest_resolvable_version_details&.fetch(:version)
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            existing_version: dependency.version,
            remove_git_source: should_switch_source_from_git_to_rubygems?,
            latest_version: latest_version_details&.fetch(:version)&.to_s,
            latest_resolvable_version:
              latest_resolvable_version_details&.fetch(:version)&.to_s
          ).updated_requirements
        end

        private

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def latest_version_for_git_dependency
          latest_release =
            latest_version_details(remove_git_source: true)&.
            fetch(:version)

          return latest_release if git_branch_or_ref_in_release?(latest_release)
          return dependency.version if git_commit_checker.pinned?
          latest_version_details(remove_git_source: false).fetch(:commit_sha)
        end

        def latest_version_details(remove_git_source: false)
          if remove_git_source
            @latest_version_details_without_git_source ||=
              version_resolver(remove_git_source: true).
              latest_version_details
          else
            @latest_version_details_with_git_source ||=
              version_resolver(remove_git_source: false).
              latest_version_details
          end
        end

        def latest_resolvable_version_for_git_dependency
          latest_release = latest_resolvable_version_without_git_source

          return latest_release if git_branch_or_ref_in_release?(latest_release)
          return dependency.version if git_commit_checker.pinned?
          latest_resolvable_version_details(remove_git_source: false).
            fetch(:commit_sha)
        end

        def latest_resolvable_version_without_git_source
          return nil unless latest_version.is_a?(Gem::Version)
          latest_resolvable_version_details(remove_git_source: true)&.
          fetch(:version)
        rescue Dependabot::DependencyFileNotResolvable
          nil
        end

        def latest_resolvable_version_details(remove_git_source: false)
          if remove_git_source
            @latest_resolvable_version_details_without_git_source ||=
              version_resolver(remove_git_source: true).
              latest_resolvable_version_details
          else
            @latest_resolvable_version_details_with_git_source ||=
              version_resolver(remove_git_source: false).
              latest_resolvable_version_details
          end
        end

        def git_branch_or_ref_in_release?(release)
          return false unless release
          git_commit_checker.branch_or_ref_in_release?(release)
        end

        def should_switch_source_from_git_to_rubygems?
          return false unless git_dependency?
          return false if latest_resolvable_version_for_git_dependency.nil?

          Gem::Version.new(latest_resolvable_version_for_git_dependency)
          true
        rescue ArgumentError
          false
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              github_access_token: github_access_token
            )
        end

        def version_resolver(remove_git_source:)
          prepared_dependency_files =
            prepared_dependency_files(remove_git_source: remove_git_source)

          VersionResolver.new(
            dependency: dependency,
            dependency_files: prepared_dependency_files,
            github_access_token: github_access_token
          )
        end

        def prepared_dependency_files(remove_git_source:)
          FilePreparer.new(
            dependency: dependency,
            dependency_files: dependency_files,
            remove_git_source: remove_git_source
          ).prepared_dependency_files
        end
      end
    end
  end
end
