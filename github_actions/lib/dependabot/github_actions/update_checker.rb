# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/requirement"
require "dependabot/github_actions/version"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module GithubActions
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(
          T.must(latest_version_finder).latest_release_version,
          T.nilable(T.any(String, Gem::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # Resolvability isn't an issue for GitHub Actions.
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        # No concept of "unlocking" for GitHub Actions (since no lockfile)
        dependency.version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        # Resolvability isn't an issue for GitHub Actions.
        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        @lowest_security_fix_version ||= T.let(
          T.must(latest_version_finder).lowest_security_fix_release&.fetch(:version),
          T.nilable(Dependabot::Version)
        )
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dependency.requirements.map do |req|
          source = req[:source]
          updated = updated_ref(source)
          next req unless updated

          current = source[:ref]

          # Maintain a short git hash only if it matches the latest
          if req[:type] == "git" &&
             git_commit_checker.ref_looks_like_commit_sha?(updated) &&
             git_commit_checker.ref_looks_like_commit_sha?(current) &&
             updated.start_with?(current)
            next req
          end

          new_source = source.merge(ref: updated)
          req.merge(source: new_source)
        end
      end

      private

      sig { returns(T.nilable(Dependabot::GithubActions::UpdateChecker::LatestVersionFinder)) }
      def latest_version_finder
        @latest_version_finder ||=
          T.let(
            LatestVersionFinder.new(
              dependency: dependency,
              credentials: credentials,
              dependency_files: dependency_files,
              security_advisories: security_advisories,
              ignored_versions: ignored_versions,
              raise_on_ignored: raise_on_ignored,
              cooldown_options: update_cooldown
            ),
            T.nilable(Dependabot::GithubActions::UpdateChecker::LatestVersionFinder)
          )
      end

      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      def active_advisories
        security_advisories.select do |advisory|
          version = git_commit_checker.most_specific_tag_equivalent_to_pinned_ref
          version.nil? ? false : advisory.vulnerable?(version_class.new(version))
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for GitHub Actions
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { params(source: T.nilable(T::Hash[Symbol, String])).returns(T.nilable(String)) }
      def updated_ref(source)
        # TODO: Support Docker sources
        return unless git_commit_checker.git_dependency?

        if vulnerable? && (new_tag = T.must(latest_version_finder).lowest_security_fix_release)
          return new_tag.fetch(:tag)
        end

        source_git_commit_checker = git_helper.git_commit_checker_for(source)

        # Return the git tag if updating a pinned version
        if source_git_commit_checker.pinned_ref_looks_like_version? &&
           (new_tag = T.must(latest_version_finder).latest_version_tag)
          return new_tag.fetch(:tag)
        end

        # Return the pinned git commit if one is available
        if source_git_commit_checker.pinned_ref_looks_like_commit_sha? &&
           (new_commit_sha = latest_commit_sha)
          return new_commit_sha
        end

        # Otherwise we can't update the ref
        nil
      end

      sig { returns(T.nilable(String)) }
      def latest_commit_sha
        new_tag = T.must(latest_version_finder).latest_version_tag
        return unless new_tag

        new_tag.fetch(:commit_sha)
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(git_helper.git_commit_checker, T.nilable(Dependabot::GitCommitChecker))
      end

      sig { returns(Dependabot::GithubActions::Helpers::Githelper) }
      def git_helper
        Helpers::Githelper.new(
          dependency: dependency,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          consider_version_branches_pinned: false,
          dependency_source_details: nil
        )
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("github_actions", Dependabot::GithubActions::UpdateChecker)
