# typed: true
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"
require "dependabot/git_commit_checker"
require "dependabot/swift/native_requirement"
require "dependabot/swift/file_updater/manifest_updater"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"

      def latest_version
        @latest_version ||= fetch_latest_version
      end

      def latest_resolvable_version
        @latest_resolvable_version ||= fetch_latest_resolvable_version
      end

      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      def lowest_security_fix_version
        @lowest_security_fix_version ||= fetch_lowest_security_fix_version
      end

      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        return @lowest_resolvable_security_fix_version if defined?(@lowest_resolvable_security_fix_version)

        @lowest_resolvable_security_fix_version = fetch_lowest_resolvable_security_fix_version
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: old_requirements,
          target_version: preferred_resolvable_version
        ).updated_requirements
      end

      private

      def old_requirements
        dependency.requirements
      end

      def fetch_latest_version
        return unless git_commit_checker.pinned_ref_looks_like_version? && latest_version_tag

        latest_version_tag.fetch(:version)
      end

      def fetch_lowest_security_fix_version
        return unless git_commit_checker.pinned_ref_looks_like_version? && latest_version_tag

        lowest_security_fix_version_tag.fetch(:version)
      end

      def fetch_latest_resolvable_version
        latest_resolvable_version = version_resolver_for(unlocked_requirements).latest_resolvable_version
        return current_version unless latest_resolvable_version

        Version.new(latest_resolvable_version)
      end

      def fetch_lowest_resolvable_security_fix_version
        lowest_resolvable_security_fix_version = version_resolver_for(
          force_lowest_security_fix_requirements
        ).latest_resolvable_version
        return unless lowest_resolvable_security_fix_version

        Version.new(lowest_resolvable_security_fix_version)
      end

      def version_resolver_for(requirements)
        VersionResolver.new(
          dependency: dependency,
          manifest: prepare_manifest_for(requirements),
          lockfile: lockfile,
          repo_contents_path: repo_contents_path,
          credentials: credentials
        )
      end

      def unlocked_requirements
        NativeRequirement.map_requirements(old_requirements) do |_old_requirement|
          "\"#{dependency.version}\"...\"#{latest_version}\""
        end
      end

      def force_lowest_security_fix_requirements
        NativeRequirement.map_requirements(old_requirements) do |_old_requirement|
          "\"#{lowest_security_fix_version}\"...\"#{lowest_security_fix_version}\""
        end
      end

      def prepare_manifest_for(new_requirements)
        DependencyFile.new(
          name: manifest.name,
          content: FileUpdater::ManifestUpdater.new(
            manifest.content,
            old_requirements: old_requirements,
            new_requirements: new_requirements
          ).updated_manifest_content,
          directory: manifest.directory
        )
      end

      def manifest
        @manifest ||= dependency_files.find { |file| file.name == "Package.swift" }
      end

      def lockfile
        @lockfile ||= dependency_files.find { |file| file.name == "Package.resolved" }
      end

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Swift (yet)
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
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

      def latest_version_tag
        git_commit_checker.local_tag_for_latest_version
      end

      def lowest_security_fix_version_tag
        tags = git_commit_checker.local_tags_for_allowed_versions
        find_lowest_secure_version(tags)
      end

      def find_lowest_secure_version(tags)
        relevant_tags = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(tags, security_advisories)
        relevant_tags = filter_lower_tags(relevant_tags)

        relevant_tags.min_by { |tag| tag.fetch(:version) }
      end

      def filter_lower_tags(tags_array)
        return tags_array unless current_version

        tags_array
          .select { |tag| tag.fetch(:version) > current_version }
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("swift", Dependabot::Swift::UpdateChecker)
