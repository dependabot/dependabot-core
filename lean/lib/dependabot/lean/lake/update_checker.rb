# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"
require "dependabot/lean"

module Dependabot
  module Lean
    module Lake
      class UpdateChecker < Dependabot::UpdateCheckers::Base
        extend T::Sig

        sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
        def latest_version
          @latest_version ||= T.let(
            fetch_latest_version,
            T.nilable(T.any(String, Dependabot::Version))
          )
        end

        sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
        def latest_resolvable_version
          # For Lake packages, resolvability depends on running lake update
          # For now, assume if there's a newer version, it's resolvable
          latest_version
        end

        sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
        def latest_resolvable_version_with_no_unlock
          # No concept of "unlocking" for git-based Lake packages
          dependency.version
        end

        sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          # Lake package requirements include the URL and branch
          # We update the version (commit SHA) but keep the same source
          dependency.requirements.map do |req|
            req.merge(requirement: nil)
          end
        end

        private

        sig { override.returns(T::Boolean) }
        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't relevant for git-based packages
          false
        end

        sig { override.returns(T::Array[Dependabot::Dependency]) }
        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        sig { returns(T.nilable(String)) }
        def fetch_latest_version
          return dependency.version unless git_dependency?

          git_commit_checker.head_commit_for_current_branch
        rescue Dependabot::GitDependencyReferenceNotFound
          # If we can't find the branch, fall back to current version
          dependency.version
        end

        sig { returns(T::Boolean) }
        def git_dependency?
          source_details = dependency.source_details
          return false unless source_details

          source_details[:type] == "git"
        end

        sig { returns(Dependabot::GitCommitChecker) }
        def git_commit_checker
          @git_commit_checker ||= T.let(
            Dependabot::GitCommitChecker.new(
              dependency: dependency,
              credentials: credentials,
              dependency_source_details: dependency.source_details
            ),
            T.nilable(Dependabot::GitCommitChecker)
          )
        end
      end
    end
  end
end
