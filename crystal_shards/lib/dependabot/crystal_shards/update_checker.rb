# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"
require "dependabot/errors"
require "dependabot/crystal_shards/version"
require "dependabot/crystal_shards/requirement"

module Dependabot
  module CrystalShards
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/requirements_updater"

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        return nil if path_dependency?

        @latest_version ||= T.let(
          (latest_version_for_git_dependency if git_dependency?),
          T.nilable(T.any(String, Dependabot::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version
        return nil if path_dependency?

        @latest_resolvable_version ||= T.let(
          latest_version,
          T.nilable(T.any(String, Dependabot::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        return nil if path_dependency?

        @latest_resolvable_version_with_no_unlock ||= T.let(
          (latest_resolvable_commit_with_unchanged_git_source if git_dependency?),
          T.nilable(T.any(String, Dependabot::Version))
        )
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          target_version: preferred_resolvable_version&.to_s,
          source: updated_source
        ).updated_requirements
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        return nil if path_dependency?

        latest_version_finder.lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        lowest_security_fix_version
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

      sig { returns(LatestVersionFinder) }
      def latest_version_finder
        @latest_version_finder ||= T.let(
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            cooldown_options: update_cooldown,
            raise_on_ignored: raise_on_ignored
          ),
          T.nilable(LatestVersionFinder)
        )
      end

      sig { returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version_for_git_dependency
        return git_commit_checker.head_commit_for_current_branch unless git_commit_checker.pinned?

        if git_commit_checker.pinned_ref_looks_like_version?
          latest_tag = git_commit_checker.local_tag_for_latest_version
          return version_from_tag(latest_tag) || dependency.version
        end

        dependency.version
      end

      sig { params(tag: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(Dependabot::Version)) }
      def version_from_tag(tag)
        return nil unless tag

        tag_name = tag[:tag]
        return nil unless tag_name

        version_string = tag_name.to_s.gsub(/^v/, "")
        return nil unless Dependabot::CrystalShards::Version.correct?(version_string)

        Dependabot::CrystalShards::Version.new(version_string)
      end

      sig { returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_commit_with_unchanged_git_source
        return nil unless git_dependency?

        git_commit_checker.head_commit_for_current_branch
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def updated_source
        return dependency_source_details unless git_dependency?

        if git_commit_checker.pinned_ref_looks_like_version?
          new_tag = git_commit_checker.local_tag_for_latest_version
          source_details = dependency_source_details
          tag_ref = new_tag&.dig(:tag)
          return source_details.merge(ref: tag_ref) if tag_ref && source_details
        end

        dependency_source_details
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def dependency_source_details
        T.cast(dependency.source_details, T.nilable(T::Hash[Symbol, T.untyped]))
      end

      sig { returns(T::Boolean) }
      def git_dependency?
        git_commit_checker.git_dependency?
      end

      sig { returns(T::Boolean) }
      def path_dependency?
        dependency.source_type == "path"
      end

      sig { returns(GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored
          ),
          T.nilable(GitCommitChecker)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("crystal_shards", Dependabot::CrystalShards::UpdateChecker)
