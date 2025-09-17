# typed: strict
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
      extend T::Sig

      require_relative "update_checker/file_preparer"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"
      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(
          if git_dependency?
            latest_version_for_git_dependency
          else
            latest_release_from_hex_registry || latest_resolvable_version
          end,
          T.nilable(T.any(String, Dependabot::Version, Gem::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version, Gem::Version))) }
      def latest_resolvable_version
        @latest_resolvable_version ||= T.let(
          if git_dependency?
            latest_resolvable_version_for_git_dependency
          else
            fetch_latest_resolvable_version(unlock_requirement: true)
          end,
          T.nilable(T.any(String, Dependabot::Version, Gem::Version))
        )
      end

      sig { override.returns(T.any(String, T.nilable(Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        @latest_resolvable_version_with_no_unlock = T.let(
          nil, T.any(String, T.nilable(Dependabot::Version))
        )

        @latest_resolvable_version_with_no_unlock ||=
          if git_dependency?
            latest_resolvable_commit_with_unchanged_git_source
          else
            fetch_latest_resolvable_version(unlock_requirement: false)
          end
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          updated_source: updated_source,
          latest_resolvable_version: latest_resolvable_version&.to_s
        ).updated_requirements
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Elixir (yet)
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T.any(String, T.nilable(Dependabot::Version))) }
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
          return T.must(new_tag).fetch(:commit_sha)
        end

        # If the dependency is pinned then there's nothing we can do.
        dependency.version
      end

      sig { returns(T.any(String, T.nilable(Dependabot::Version))) }
      def latest_resolvable_commit_with_unchanged_git_source
        fetch_latest_resolvable_version(unlock_requirement: false)
      rescue SharedHelpers::HelperSubprocessFailed,
             Dependabot::DependencyFileNotResolvable => e
        # Resolution may fail, as Elixir updates straight to the tip of the
        # branch. Just return `nil` if it does (so no update).
        return if e.message.include?("resolution failed")

        raise e
      end

      sig { returns(T::Boolean) }
      def git_dependency?
        git_commit_checker.git_dependency?
      end

      sig { returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version_for_git_dependency
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

      sig { returns(T::Boolean) }
      def latest_git_tag_is_resolvable?
        return T.must(@git_tag_resolvable) if @latest_git_tag_is_resolvable_checked

        @latest_git_tag_is_resolvable_checked = T.let(true, T.nilable(T::Boolean))

        return false if git_commit_checker.local_tag_for_latest_version.nil?

        replacement_tag = git_commit_checker.local_tag_for_latest_version

        prepared_files = FilePreparer.new(
          dependency: dependency,
          dependency_files: dependency_files,
          replacement_git_pin: T.must(replacement_tag).fetch(:tag)
        ).prepared_dependency_files

        resolver_result = VersionResolver.new(
          dependency: dependency,
          prepared_dependency_files: prepared_files,
          original_dependency_files: dependency_files,
          credentials: credentials
        ).latest_resolvable_version

        @git_tag_resolvable = !resolver_result.nil?
        @git_tag_resolvable
      rescue SharedHelpers::HelperSubprocessFailed,
             Dependabot::DependencyFileNotResolvable => e
        raise e unless e.message.include?("resolution failed")

        @git_tag_resolvable = T.let(false, T.nilable(T::Boolean))
        false
      end

      sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def updated_source
        # Never need to update source, unless a git_dependency
        return dependency_source_details unless git_dependency?

        # Update the git tag if updating a pinned version
        if git_commit_checker.pinned_ref_looks_like_version? &&
           latest_git_tag_is_resolvable?
          new_tag = git_commit_checker.local_tag_for_latest_version
          return T.must(dependency_source_details).merge(ref: T.must(new_tag).fetch(:tag))
        end

        # Otherwise return the original source
        dependency_source_details
      end

      sig { returns(T.nilable(T::Hash[T.any(String, Symbol), T.untyped])) }
      def dependency_source_details
        dependency.source_details
      end

      sig do
        params(unlock_requirement: T.any(T.nilable(Symbol), T::Boolean))
          .returns(T.any(String, T.nilable(Dependabot::Version)))
      end
      def fetch_latest_resolvable_version(unlock_requirement:)
        @latest_resolvable_version_hash ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
        @latest_resolvable_version_hash[unlock_requirement] ||=
          version_resolver(unlock_requirement: unlock_requirement)
          .latest_resolvable_version
      end

      sig { params(unlock_requirement: T.any(T.nilable(Symbol), T::Boolean)).returns(VersionResolver) }
      def version_resolver(unlock_requirement:)
        @version_resolver ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
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

      sig do
        params(unlock_requirement: T.any(T.nilable(Symbol), T::Boolean),
               latest_allowable_version: T.nilable(Dependabot::Version))
          .returns(T::Array[Dependabot::DependencyFile])
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

      sig { returns(T.nilable(Dependabot::Version)) }
      def latest_release_from_hex_registry
        @latest_release_from_hex_registry ||=
          T.let(LatestVersionFinder.new(
            dependency: dependency,
            credentials: credentials,
            dependency_files: dependency_files,
            security_advisories: security_advisories,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            cooldown_options: update_cooldown
          ).release_version,
                T.nilable(T.nilable(Dependabot::Version)))
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ),
          T.nilable(Dependabot::GitCommitChecker)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("hex", Dependabot::Hex::UpdateChecker)
