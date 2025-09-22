# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/requirement"
require "dependabot/github_actions/version"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"
require "sorbet-runtime"

module Dependabot
  module GithubActions
    module Helpers
      class Githelper
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            raise_on_ignored: T::Boolean,
            consider_version_branches_pinned: T::Boolean,
            dependency_source_details: T.nilable(T::Hash[Symbol, String])
          )
            .void
        end
        def initialize(
          dependency:,
          credentials:,
          ignored_versions: [],
          raise_on_ignored: false,
          consider_version_branches_pinned: false,
          dependency_source_details: nil
        )
          @dependency = dependency
          @credentials = credentials
          @ignored_versions = ignored_versions
          @raise_on_ignored = raise_on_ignored
          @consider_version_branches_pinned = consider_version_branches_pinned
          @dependency_source_details = dependency_source_details
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { returns(Dependabot::GitCommitChecker) }
        def git_commit_checker
          @git_commit_checker ||= T.let(
            git_commit_checker_for(nil),
            T.nilable(Dependabot::GitCommitChecker)
          )
        end

        sig { params(source: T.nilable(T::Hash[Symbol, String])).returns(Dependabot::GitCommitChecker) }
        def git_commit_checker_for(source)
          @git_commit_checkers ||= T.let(
            {},
            T.nilable(T::Hash[T.nilable(T::Hash[Symbol, String]), Dependabot::GitCommitChecker])
          )

          @git_commit_checkers[source] ||= Dependabot::GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            consider_version_branches_pinned: true,
            dependency_source_details: source
          )
        end
      end
    end
  end
end
