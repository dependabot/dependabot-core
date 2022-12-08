# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/bundler/file_updater/requirement_replacer"
require "dependabot/bundler/version"
require "dependabot/git_commit_checker"
module Dependabot
  module Bundler
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/force_updater"
      require_relative "update_checker/file_preparer"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"
      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/conflicting_dependency_resolver"

      def latest_version
        return latest_version_for_git_dependency if git_dependency?

        latest_version_details&.fetch(:version)
      end

      def latest_resolvable_version
        return latest_resolvable_version_for_git_dependency if git_dependency?

        latest_resolvable_version_details&.fetch(:version)
      end

      def lowest_security_fix_version
        latest_version_finder(remove_git_source: false).
          lowest_security_fix_version
      end

      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?
        return latest_resolvable_version if git_dependency?

        lowest_fix =
          latest_version_finder(remove_git_source: false).
          lowest_security_fix_version
        return unless lowest_fix

        resolvable?(lowest_fix) ? lowest_fix : latest_resolvable_version
      end

      def latest_resolvable_version_with_no_unlock
        current_ver = dependency.version
        return current_ver if git_dependency? && git_commit_checker.pinned?

        @latest_resolvable_version_detail_with_no_unlock ||=
          version_resolver(remove_git_source: false, unlock_requirement: false).
          latest_resolvable_version_details

        if git_dependency?
          @latest_resolvable_version_detail_with_no_unlock&.fetch(:commit_sha)
        else
          @latest_resolvable_version_detail_with_no_unlock&.fetch(:version)
        end
      end

      def updated_requirements
        latest_version_for_req_updater = latest_version_details&.fetch(:version)&.to_s
        latest_resolvable_version_for_req_updater = preferred_resolvable_version_details&.fetch(:version)&.to_s

        RequirementsUpdater.new(
          requirements: dependency.requirements,
          update_strategy: requirements_update_strategy,
          updated_source: updated_source,
          latest_version: latest_version_for_req_updater,
          latest_resolvable_version: latest_resolvable_version_for_req_updater
        ).updated_requirements
      end

      def requirements_unlocked_or_can_be?
        dependency.requirements.
          select { |r| requirement_class.new(r[:requirement]).specific? }.
          all? do |req|
            file = dependency_files.find { |f| f.name == req.fetch(:file) }
            updated = FileUpdater::RequirementReplacer.new(
              dependency: dependency,
              file_type: file.name.end_with?("gemspec") ? :gemspec : :gemfile,
              updated_requirement: "whatever"
            ).rewrite(file.content)

            updated != file.content
          end
      end

      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        return @requirements_update_strategy.to_sym if @requirements_update_strategy

        # Otherwise, widen ranges for libraries and bump versions for apps
        dependency.version.nil? ? :bump_versions_if_necessary : :bump_versions
      end

      def conflicting_dependencies
        ConflictingDependencyResolver.new(
          dependency_files: dependency_files,
          repo_contents_path: repo_contents_path,
          credentials: credentials,
          options: options
        ).conflicting_dependencies(
          dependency: dependency,
          target_version: lowest_security_fix_version
        )
      end

      private

      def latest_version_resolvable_with_full_unlock?
        return false unless latest_version

        updated_dependencies = force_updater.updated_dependencies

        updated_dependencies.none? do |dep|
          old_version = dep.previous_version
          next unless Gem::Version.correct?(old_version)
          next if Gem::Version.new(old_version).prerelease?

          Gem::Version.new(dep.version).prerelease?
        end
      rescue Dependabot::DependencyFileNotResolvable
        false
      end

      def updated_dependencies_after_full_unlock
        force_updater.updated_dependencies
      end

      def preferred_resolvable_version_details
        return { version: lowest_resolvable_security_fix_version } if vulnerable?

        latest_resolvable_version_details
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def resolvable?(version)
        @resolvable ||= {}
        return @resolvable[version] if @resolvable.key?(version)

        @resolvable[version] =
          begin
            ForceUpdater.new(
              dependency: dependency,
              dependency_files: dependency_files,
              repo_contents_path: repo_contents_path,
              credentials: credentials,
              target_version: version,
              requirements_update_strategy: requirements_update_strategy,
              update_multiple_dependencies: false,
              options: options
            ).updated_dependencies
            true
          rescue Dependabot::DependencyFileNotResolvable
            false
          end
      end

      def git_tag_resolvable?(tag)
        @git_tag_resolvable ||= {}
        return @git_tag_resolvable[tag] if @git_tag_resolvable.key?(tag)

        @git_tag_resolvable[tag] =
          begin
            VersionResolver.new(
              dependency: dependency,
              unprepared_dependency_files: dependency_files,
              repo_contents_path: repo_contents_path,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: raise_on_ignored,
              replacement_git_pin: tag,
              options: options
            ).latest_resolvable_version_details
            true
          rescue Dependabot::DependencyFileNotResolvable
            false
          end
      end

      def latest_version_details(remove_git_source: false)
        @latest_version_details ||= {}
        @latest_version_details[remove_git_source] ||=
          latest_version_finder(remove_git_source: remove_git_source).
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
        return git_commit_checker.head_commit_for_current_branch unless git_commit_checker.pinned?

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
        return latest_resolvable_commit_with_unchanged_git_source unless git_commit_checker.pinned?

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
        details = latest_resolvable_version_details(remove_git_source: false)

        # If this dependency has a git version in the Gemfile.lock but not in
        # the Gemfile (i.e., because they're out-of-sync) we might not get a
        # commit_sha back from Bundler. In that case, return `nil`.
        return unless details&.key?(:commit_sha)

        details.fetch(:commit_sha)
      rescue Dependabot::DependencyFileNotResolvable
        nil
      end

      def latest_git_tag_is_resolvable?
        latest_tag_details = git_commit_checker.local_tag_for_latest_version
        return false unless latest_tag_details

        git_tag_resolvable?(latest_tag_details.fetch(:tag))
      end

      def git_branch_or_ref_in_release?(release)
        return false unless release

        git_commit_checker.branch_or_ref_in_release?(release)
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
        sources =
          dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

        raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

        sources.first
      end

      def force_updater
        @force_updater ||=
          ForceUpdater.new(
            dependency: dependency,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials,
            target_version: latest_version,
            requirements_update_strategy: requirements_update_strategy,
            options: options
          )
      end

      def git_commit_checker
        @git_commit_checker ||=
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          )
      end

      def version_resolver(remove_git_source:, unlock_requirement: true)
        @version_resolver ||= {}
        @version_resolver[remove_git_source] ||= {}
        @version_resolver[remove_git_source][unlock_requirement] ||=
          VersionResolver.new(
            dependency: dependency,
            unprepared_dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            remove_git_source: remove_git_source,
            unlock_requirement: unlock_requirement,
            latest_allowable_version: latest_version,
            options: options
          )
      end

      def latest_version_finder(remove_git_source:)
        @latest_version_finder ||= {}
        @latest_version_finder[remove_git_source] ||=
          begin
            prepared_dependency_files = prepared_dependency_files(
              remove_git_source: remove_git_source,
              unlock_requirement: true
            )

            LatestVersionFinder.new(
              dependency: dependency,
              dependency_files: prepared_dependency_files,
              repo_contents_path: repo_contents_path,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: raise_on_ignored,
              security_advisories: security_advisories,
              options: options
            )
          end
      end

      def prepared_dependency_files(remove_git_source:, unlock_requirement:,
                                    latest_allowable_version: nil)
        FilePreparer.new(
          dependency: dependency,
          dependency_files: dependency_files,
          remove_git_source: remove_git_source,
          unlock_requirement: unlock_requirement,
          latest_allowable_version: latest_allowable_version
        ).prepared_dependency_files
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("bundler", Dependabot::Bundler::UpdateChecker)
