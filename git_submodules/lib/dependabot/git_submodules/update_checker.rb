# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/git_submodules/version"
require "dependabot/git_commit_checker"
require "dependabot/git_submodules/requirement"

module Dependabot
  module GitSubmodules
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

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
        # Resolvability isn't an issue for submodules.
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        # No concept of "unlocking" for submodules
        latest_version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        # Submodule requirements are the URL and branch to use for the
        # submodule. We never want to update either.
        dependency.requirements
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for submodules
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T.nilable(String)) }
      def fetch_latest_version
        git_commit_checker = Dependabot::GitCommitChecker.new(
          dependency: dependency,
          credentials: credentials
        )

        git_commit_checker.head_commit_for_current_branch
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("submodules", Dependabot::GitSubmodules::UpdateChecker)
