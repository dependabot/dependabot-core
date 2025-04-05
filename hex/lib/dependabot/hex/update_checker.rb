# typed: true
# frozen_string_literal: true

require "excon"
require "dependabot/git_commit_checker"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/registry_client"

require "json"

module Dependabot
  module Hex
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/file_preparer"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"

      def latest_version
        @latest_version ||=
          if git_dependency?
            latest_version_for_git_dependency
          else
            latest_release_from_hex_registry || latest_resolvable_version
          end
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
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          updated_source: updated_source,
          latest_resolvable_version: latest_resolvable_version&.to_s
        ).updated_requirements
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Elixir (yet)
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def latest_version_for_git_dependency
        latest_git_version_sha
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

      def latest_resolvable_commit_with_unchanged_git_source
        fetch_latest_resolvable_version(unlock_requirement: false)
      rescue SharedHelpers::HelperSubprocessFailed,
             Dependabot::DependencyFileNotResolvable => e
        # Resolution may fail, as Elixir updates straight to the tip of the
        # branch. Just return `nil` if it does (so no update).
        return if e.message.include?("resolution failed")

        raise e
      end

      def git_dependency?
        git_commit_checker.git_dependency?
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

        resolver_result = VersionResolver.new(
          dependency: dependency,
          prepared_dependency_files: prepared_files,
          original_dependency_files: dependency_files,
          credentials: credentials
        ).latest_resolvable_version

        @git_tag_resolvable = !resolver_result.nil?
      rescue SharedHelpers::HelperSubprocessFailed,
             Dependabot::DependencyFileNotResolvable => e
        raise e unless e.message.include?("resolution failed")

        @git_tag_resolvable = false
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

      def fetch_latest_resolvable_version(unlock_requirement:)
        @latest_resolvable_version_hash ||= {}
        @latest_resolvable_version_hash[unlock_requirement] ||=
          version_resolver(unlock_requirement: unlock_requirement)
          .latest_resolvable_version
      end

      def version_resolver(unlock_requirement:)
        @version_resolver ||= {}
        @version_resolver[unlock_requirement] ||=
          begin
            prepared_dependency_files = prepared_dependency_files(
              unlock_requirement: unlock_requirement,
              latest_allowable_version: latest_release_from_hex_registry
            )

            VersionResolver.new(
              dependency: dependency,
              prepared_dependency_files: prepared_dependency_files,
              original_dependency_files: dependency_files,
              credentials: credentials
            )
          end
      end

      def prepared_dependency_files(unlock_requirement:,
                                    latest_allowable_version: nil)
        FilePreparer.new(
          dependency: dependency,
          dependency_files: dependency_files,
          unlock_requirement: unlock_requirement,
          latest_allowable_version: latest_allowable_version
        ).prepared_dependency_files
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def latest_release_from_hex_registry
        @latest_release_from_hex_registry ||=
          begin
            versions = hex_registry_response&.fetch("releases", []) || []
            versions =
              versions
              .select { |release| version_class.correct?(release["version"]) }
              .map { |release| version_class.new(release["version"]) }

            versions.reject!(&:prerelease?) unless wants_prerelease?

            filtered = versions.reject do |v|
              ignore_requirements.any? { |r| r.satisfied_by?(v) }
            end

            if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions).any?
              raise AllVersionsIgnored
            end

            filtered.max
          end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def filter_lower_versions(versions_array)
        return versions_array unless current_version

        versions_array.select do |version|
          version > current_version
        end
      end

      def hex_registry_response
        return @hex_registry_response if @hex_registry_requested

        @hex_registry_requested = true

        response = Dependabot::RegistryClient.get(url: dependency_url)
        return unless response.status == 200

        @hex_registry_response = JSON.parse(response.body)
      rescue Excon::Error::Socket, Excon::Error::Timeout
        nil
      end

      def wants_prerelease?
        return true if current_version&.prerelease?

        dependency.requirements.any? do |req|
          req[:requirement]&.match?(/\d-[A-Za-z0-9]/)
        end
      end

      def dependency_url
        "https://hex.pm/api/packages/#{dependency.name}"
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

Dependabot::UpdateCheckers.register("hex", Dependabot::Hex::UpdateChecker)
