# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler < Dependabot::UpdateCheckers::Base
        require_relative "bundler/force_updater"
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

        def latest_resolvable_version_with_no_unlock
          if git_dependency? && git_commit_checker.pinned?
            return dependency.version
          end

          @latest_resolvable_version_detail_with_no_unlock ||=
            version_resolver(
              remove_git_source: false,
              unlock_requirement: false
            ).latest_resolvable_version_details

          if git_dependency?
            @latest_resolvable_version_detail_with_no_unlock&.fetch(:commit_sha)
          else
            @latest_resolvable_version_detail_with_no_unlock&.fetch(:version)
          end
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            library: library?,
            updated_source: updated_source,
            latest_version: latest_version_details&.fetch(:version)&.to_s,
            latest_resolvable_version:
              latest_resolvable_version_details&.fetch(:version)&.to_s
          ).updated_requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          return false unless latest_version
          force_updater.updated_dependencies
          true
        rescue Dependabot::DependencyFileNotResolvable
          false
        end

        def library?
          dependency.version.nil?
        end

        def updated_dependencies_after_full_unlock
          force_updater.updated_dependencies
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def latest_version_details(remove_git_source: false)
          @latest_version_details ||= {}
          @latest_version_details[remove_git_source] ||=
            version_resolver(remove_git_source: remove_git_source).
            latest_version_details
        end

        def latest_resolvable_version_details(remove_git_source: false)
          @latest_resolvable_version_details ||= {}
          @latest_resolvable_version_details[remove_git_source] ||=
            version_resolver(remove_git_source: remove_git_source).
            latest_resolvable_version_details
        end

        def latest_version_for_git_dependency
          latest_release =
            latest_version_details(remove_git_source: true)&.
            fetch(:version)

          # If there's been a release that includes the current pinned ref or
          # that the current branch is behind, we switch to that release.
          return latest_release if git_branch_or_ref_in_release?(latest_release)

          # Otherwise, if the gem isn't pinned, the latest version is just the
          # latest commit for the specified branch.
          unless git_commit_checker.pinned?
            return git_commit_checker.head_commit_for_current_branch
          end

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag. The latest version will then be the SHA
          # of the latest tag that looks like a version.
          if git_commit_checker.pinned_ref_looks_like_version?
            latest_tag = git_commit_checker.local_tag_for_latest_version
            return latest_tag&.fetch(:tag_sha) || dependency.version
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          dependency.version
        end

        def latest_resolvable_version_for_git_dependency
          latest_release = latest_resolvable_version_without_git_source

          # If there's a resolvable release that includes the current pinned
          # ref or that the current branch is behind, we switch to that release.
          return latest_release if git_branch_or_ref_in_release?(latest_release)

          # Otherwise, if the gem isn't pinned, the latest version is just the
          # latest commit for the specified branch.
          unless git_commit_checker.pinned?
            return latest_resolvable_commit_with_unchanged_git_source
          end

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag. The latest version will then be the SHA
          # of the latest tag that looks like a version.
          if git_commit_checker.pinned_ref_looks_like_version? &&
             latest_git_tag_is_resolvable?
            new_tag = git_commit_checker.local_tag_for_latest_version
            return new_tag.fetch(:tag_sha)
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          dependency.version
        end

        def latest_resolvable_version_without_git_source
          return nil unless latest_version.is_a?(Gem::Version)
          latest_resolvable_version_details(remove_git_source: true)&.
          fetch(:version)
        rescue Dependabot::DependencyFileNotResolvable
          nil
        end

        def latest_resolvable_commit_with_unchanged_git_source
          latest_resolvable_version_details(remove_git_source: false).
            fetch(:commit_sha)
        rescue Dependabot::DependencyFileNotResolvable
          nil
        end

        def latest_git_tag_is_resolvable?
          return @git_tag_resolvable if @latest_git_tag_is_resolvable_checked
          @latest_git_tag_is_resolvable_checked = true

          return false if git_commit_checker.local_tag_for_latest_version.nil?
          replacement_tag = git_commit_checker.local_tag_for_latest_version

          prepared_files = FilePreparer.new(
            dependency: dependency,
            dependency_files: dependency_files,
            replacement_git_pin: replacement_tag.fetch(:tag)
          ).prepared_dependency_files

          VersionResolver.new(
            dependency: dependency,
            dependency_files: prepared_files,
            credentials: credentials
          ).latest_resolvable_version_details

          @git_tag_resolvable = true
        rescue Dependabot::DependencyFileNotResolvable
          @git_tag_resolvable = false
        end

        def git_branch_or_ref_in_release?(release)
          return false unless release
          git_commit_checker.branch_or_ref_in_release?(release)
        end

        def updated_source
          # Never need to update source, unless a git_dependency
          return dependency_source_details unless git_dependency?

          # Source becomes `nil` if switching to default rubygems
          return nil if should_switch_source_from_git_to_rubygems?

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
          sources =
            dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

          sources.first
        end

        def should_switch_source_from_git_to_rubygems?
          return false unless git_dependency?
          return false if latest_resolvable_version_for_git_dependency.nil?

          Gem::Version.new(latest_resolvable_version_for_git_dependency)
          true
        rescue ArgumentError
          false
        end

        def force_updater
          @force_updater ||=
            ForceUpdater.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              target_version: latest_version
            )
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              github_access_token: github_access_token
            )
        end

        def version_resolver(remove_git_source:, unlock_requirement: true)
          @version_resolver ||= {}
          @version_resolver[remove_git_source] ||= {}
          @version_resolver[remove_git_source][unlock_requirement] ||=
            begin
              prepared_dependency_files = prepared_dependency_files(
                remove_git_source: remove_git_source,
                unlock_requirement: unlock_requirement
              )

              VersionResolver.new(
                dependency: dependency,
                dependency_files: prepared_dependency_files,
                credentials: credentials
              )
            end
        end

        def prepared_dependency_files(remove_git_source:, unlock_requirement:)
          FilePreparer.new(
            dependency: dependency,
            dependency_files: dependency_files,
            remove_git_source: remove_git_source,
            unlock_requirement: unlock_requirement
          ).prepared_dependency_files
        end

        def github_access_token
          credentials.
            find { |cred| cred["host"] == "github.com" }.
            fetch("password")
        end
      end
    end
  end
end
