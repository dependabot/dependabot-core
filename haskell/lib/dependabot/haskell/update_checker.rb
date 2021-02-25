# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/haskell/version"
require "dependabot/haskell/requirement"

module Dependabot
  module Haskell
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/requirements_updater"

      LAST_VERSION = />([\d\.]+)<\/\w+><\/td>/

      # The latest version of the dependency, ignoring resolvability. This is used to short-circuit update checking when the dependency is already at the latest version (since checking resolvability is typically slow).
      def latest_version
        @latest_version ||= fetch_latest_version
      end

      # The latest version of the dependency that will still allow the full dependency set to resolve.
      def latest_resolvable_version
        # hopefully we can check this by Stackage
        # TODO: alternatively, try `cabal outdated` or `cabal install`
        @stable_version ||= fetch_stable_version
      end

      # The latest version of the dependency that satisfies the dependency's current version constraints and will still allow the full dependency set to resolve.
      def latest_resolvable_version_with_no_unlock
        # No lockfile for Cabal
        # TODO: support Stack which does have a Stack.yaml.lock
        dependency.version
      end

      # An updated set of requirements for the dependency that should replace the existing requirements in the manifest file. Use by the file updater class when updating the manifest file.
      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          update_strategy: requirements_update_strategy,
          updated_source: updated_source,
          latest_version: latest_version,
          latest_resolvable_version: latest_resolvable_version
        ).updated_requirements
      end

      private

      # A boolean for whether the latest version can be resolved if all other dependencies are unlocked in the manifest file. Can be set to always return `false` if multi-dependency updates aren't yet supported.
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for Cabal
        false
      end

      # And updated set of dependencies after a full unlock and update has taken place. Not required if `latest_version_resolvable_with_full_unlock?` always returns false.
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      # fetch the latest available version from Hackage
      def fetch_latest_version
        url = "http://hackage.haskell.org/package/#{dependency.name}"
        response = fetch(url)
        # css = '.properties>tbody>tr[0]>td[0]>elem[-1].text'
        latest_version = response.body.match(LAST_VERSION)
        latest_version
      end

      # fetch the stable version from Stackage
      def fetch_stable_version
        url = "https://www.stackage.org/lts/package/#{dependency.name}"
        response = fetch(url)
        version_regex = /#{dependency.name}-(\d\.)+@/
        stable_version = response.body.match(version_regex)
        stable_version
      end

      # fetch a url by http get
      def fetch(url)
        response = Excon.get(url)
        if response.status >= 400
          raise "Unhandled fetching error!\n"\
                "Status: #{response.status}\n"\
                "Body: #{response.body}"
        end
        response
      end

      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        return @requirements_update_strategy.to_sym if @requirements_update_strategy

        # Otherwise, widen ranges for libraries and bump versions for apps
        dependency.version.nil? ? :bump_versions_if_necessary : :bump_versions
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def updated_source
        # Never need to update source, unless a git_dependency
        return dependency_source_details unless git_dependency?

        # Source becomes `nil` if switching away from git
        return nil if should_switch_source_from_ref_to_release?

        # Update the git tag if updating a pinned version
        if git_commit_checker.pinned_ref_looks_like_version? &&
           !git_commit_checker.local_tag_for_latest_version.nil?
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

      def should_switch_source_from_ref_to_release?
        return false unless git_dependency?
        return false if latest_resolvable_version_for_git_dependency.nil?

        Gem::Version.correct?(latest_resolvable_version_for_git_dependency)
      end

      def git_commit_checker
        @git_commit_checker ||=
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions
          )
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
        # Resolution may fail, as it updates straight to the tip of the
        # branch. Just return `nil` if it does (so no update).
        return if e.message.include?("resolution failed")

        raise e
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

      def fetch_latest_resolvable_version(unlock_requirement:)
        @latest_resolvable_version_hash ||= {}
        @latest_resolvable_version_hash[unlock_requirement] ||=
          version_resolver(unlock_requirement: unlock_requirement).
          latest_resolvable_version
      end

      def version_resolver(unlock_requirement:)
        @version_resolver ||= {}
        @version_resolver[unlock_requirement] ||=
          begin
            prepared_dependency_files = prepared_dependency_files(
              unlock_requirement: unlock_requirement,
              latest_allowable_version: latest_version
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

    end
  end
end

Dependabot::UpdateCheckers.
  register("haskell", Dependabot::Haskell::UpdateChecker)
