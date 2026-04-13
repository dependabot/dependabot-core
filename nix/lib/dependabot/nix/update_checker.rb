# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/nix/version"
require "dependabot/nix/requirement"
require "dependabot/git_commit_checker"

module Dependabot
  module Nix
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/versioned_branch_finder"

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        @latest_version ||=
          T.let(
            fetch_latest_version,
            T.nilable(T.any(String, Dependabot::Version))
          )
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        latest_version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        if ref_pinned_to_version_tag?
          updated_requirements_for_tag
        elsif ref_is_versioned_branch?
          updated_requirements_for_versioned_branch
        else
          dependency.requirements
        end
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T.nilable(String)) }
      def fetch_latest_version
        if ref_pinned_to_version_tag?
          fetch_latest_version_for_tag
        elsif ref_is_versioned_branch?
          fetch_latest_version_for_versioned_branch
        else
          fetch_latest_version_for_commit
        end
      end

      # --- Tag-pinned ref support ---

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements_for_tag
        new_tag = latest_version_tag
        return dependency.requirements unless new_tag

        dependency.requirements.map do |req|
          source = req[:source]
          next req unless source

          req.merge(source: source.merge(ref: new_tag[:tag], branch: nil))
        end
      end

      sig { returns(T.nilable(String)) }
      def fetch_latest_version_for_tag
        tag = latest_version_tag
        tag&.fetch(:commit_sha)
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def latest_version_tag
        @latest_version_tag ||= T.let(
          git_commit_checker.local_tag_for_latest_version,
          T.nilable(T::Hash[Symbol, T.untyped])
        )
      end

      # --- Versioned branch support ---

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements_for_versioned_branch
        result = latest_versioned_branch
        return dependency.requirements unless result

        dependency.requirements.map do |req|
          source = req[:source]
          next req unless source

          req.merge(source: source.merge(ref: result[:branch], branch: nil))
        end
      end

      sig { returns(T.nilable(String)) }
      def fetch_latest_version_for_versioned_branch
        result = latest_versioned_branch
        result&.fetch(:commit_sha)
      end

      sig { returns(T.nilable(T::Hash[Symbol, String])) }
      def latest_versioned_branch
        @latest_versioned_branch ||= T.let(
          versioned_branch_finder&.latest_versioned_branch,
          T.nilable(T::Hash[Symbol, String])
        )
      end

      # --- Commit-tracking (existing behavior) ---

      sig { returns(T.nilable(String)) }
      def fetch_latest_version_for_commit
        T.let(
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            cooldown_options: update_cooldown,
            raise_on_ignored: raise_on_ignored
          ).latest_tag,
          T.nilable(String)
        )
      end

      # --- Ref classification ---

      sig { returns(T::Boolean) }
      def ref_pinned_to_version_tag?
        return false unless git_commit_checker.git_dependency?
        return false unless dependency_source_ref

        git_commit_checker.pinned_ref_looks_like_version?
      end

      sig { returns(T::Boolean) }
      def ref_is_versioned_branch?
        finder = versioned_branch_finder
        return false unless finder

        finder.versioned_branch?
      end

      sig { returns(T.nilable(String)) }
      def dependency_source_ref
        dependency.source_details(allowed_types: ["git"])&.fetch(:ref, nil)
      end

      sig { returns(T.nilable(VersionedBranchFinder)) }
      def versioned_branch_finder
        ref = dependency_source_ref
        return unless ref

        @versioned_branch_finder ||= T.let(
          VersionedBranchFinder.new(
            current_ref: ref,
            dependency: dependency,
            credentials: credentials
          ),
          T.nilable(VersionedBranchFinder)
        )
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(
          Dependabot::GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored
          ),
          T.nilable(Dependabot::GitCommitChecker)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("nix", Dependabot::Nix::UpdateChecker)
