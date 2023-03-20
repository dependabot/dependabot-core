# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"
require "dependabot/terraform/requirements_updater"
require "dependabot/terraform/requirement"
require "dependabot/terraform/version"
require "dependabot/terraform/registry_client"

module Dependabot
  module Terraform
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      ELIGIBLE_SOURCE_TYPES = %w(git provider registry).freeze

      def latest_version
        return latest_version_for_git_dependency if git_dependency?
        return latest_version_for_registry_dependency if registry_dependency?
        return latest_version_for_provider_dependency if provider_dependency?
        # Other sources (mercurial, path dependencies) just return `nil`
      end

      def latest_resolvable_version
        # No concept of resolvability for terraform modules (that we're aware
        # of - there may be in future).
        latest_version
      end

      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Terraform doesn't have a lockfile
        nil
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: latest_version&.to_s,
          tag_for_latest_version: tag_for_latest_version
        ).updated_requirements
      end

      def requirements_unlocked_or_can_be?
        # If the requirement comes from a proxy URL then there's no way for
        # us to update it
        !proxy_requirement?
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for Terraform files
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def latest_version_for_registry_dependency
        return unless registry_dependency?

        return @latest_version_for_registry_dependency if @latest_version_for_registry_dependency

        versions = all_module_versions
        versions.reject!(&:prerelease?) unless wants_prerelease?
        versions.reject! { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }

        @latest_version_for_registry_dependency = versions.max
      end

      def all_module_versions
        identifier = dependency_source_details.fetch(:module_identifier)
        registry_client.all_module_versions(identifier: identifier)
      end

      def all_provider_versions
        identifier = dependency_source_details.fetch(:module_identifier)
        registry_client.all_provider_versions(identifier: identifier)
      end

      def registry_client
        @registry_client ||= begin
          hostname = dependency_source_details.fetch(:registry_hostname)
          RegistryClient.new(hostname: hostname, credentials: credentials)
        end
      end

      def latest_version_for_provider_dependency
        return unless provider_dependency?

        return @latest_version_for_provider_dependency if @latest_version_for_provider_dependency

        versions = all_provider_versions
        versions.reject!(&:prerelease?) unless wants_prerelease?
        versions.reject! { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }

        @latest_version_for_provider_dependency = versions.max
      end

      def wants_prerelease?
        current_version = dependency.version
        if current_version &&
           version_class.correct?(current_version) &&
           version_class.new(current_version).prerelease?
          return true
        end

        dependency.requirements.any? do |req|
          req[:requirement]&.match?(/\d-[A-Za-z0-9]/)
        end
      end

      def latest_version_for_git_dependency
        # If the module isn't pinned then there's nothing for us to update
        # (since there's no lockfile to update the version in). We still
        # return the latest commit for the given branch, in order to keep
        # this method consistent
        return git_commit_checker.head_commit_for_current_branch unless git_commit_checker.pinned?

        # If the dependency is pinned to a tag that looks like a version then
        # we want to update that tag. Because we don't have a lockfile, the
        # latest version is the tag itself.
        if git_commit_checker.pinned_ref_looks_like_version?
          latest_tag = git_commit_checker.local_tag_for_latest_version&.
                       fetch(:tag)
          version_rgx = GitCommitChecker::VERSION_REGEX
          return unless latest_tag.match(version_rgx)

          version = latest_tag.match(version_rgx).
                    named_captures.fetch("version")
          return version_class.new(version)
        end

        # If the dependency is pinned to a tag that doesn't look like a
        # version then there's nothing we can do.
        nil
      end

      def tag_for_latest_version
        return unless git_commit_checker.git_dependency?
        return unless git_commit_checker.pinned?
        return unless git_commit_checker.pinned_ref_looks_like_version?

        latest_tag = git_commit_checker.local_tag_for_latest_version&.
                     fetch(:tag)

        version_rgx = GitCommitChecker::VERSION_REGEX
        return unless latest_tag.match(version_rgx)

        latest_tag
      end

      def proxy_requirement?
        dependency.requirements.any? do |req|
          req.fetch(:source)&.fetch(:proxy_url, nil)
        end
      end

      def registry_dependency?
        return false if dependency_source_details.nil?

        dependency_source_details.fetch(:type) == "registry"
      end

      def provider_dependency?
        return false if dependency_source_details.nil?

        dependency_source_details.fetch(:type) == "provider"
      end

      def dependency_source_details
        sources = eligible_sources_from(dependency.requirements)

        raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

        sources.first
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def git_commit_checker
        @git_commit_checker ||=
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored
          )
      end

      def eligible_sources_from(requirements)
        requirements.
          map { |r| r.fetch(:source) }.
          select { |source| ELIGIBLE_SOURCE_TYPES.include?(source[:type].to_s) }.
          uniq.compact
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("terraform", Dependabot::Terraform::UpdateChecker)
