# typed: strong
# frozen_string_literal: true

# Method signatures for Dependabot::Clients::Bitbucket methods delegated via method_missing.
# These allow callers to use BitbucketWithRetries without T.unsafe wrappers.

module Dependabot
  module Clients
    class BitbucketWithRetries
      sig { params(repo: String, branch: String).returns(String) }
      def fetch_commit(repo, branch); end

      sig { params(repo: String).returns(String) }
      def fetch_default_branch(repo); end

      sig do
        params(
          repo: String,
          commit: T.nilable(String),
          path: T.nilable(String)
        ).returns(T::Array[T::Hash[String, T.untyped]])
      end
      def fetch_repo_contents(repo, commit = nil, path = nil); end

      sig { params(repo: String, commit: String, path: String).returns(String) }
      def fetch_file_contents(repo, commit, path); end

      sig { params(repo: String, branch_name: T.nilable(String)).returns(T::Enumerator[T::Hash[String, T.untyped]]) }
      def commits(repo, branch_name = nil); end

      sig { params(repo: String, branch_name: String).returns(T::Hash[String, T.untyped]) }
      def branch(repo, branch_name); end

      sig do
        params(
          repo: String,
          source_branch: T.nilable(String),
          target_branch: T.nilable(String),
          status: T::Array[String]
        ).returns(T::Array[T::Hash[String, T.untyped]])
      end
      def pull_requests(repo, source_branch, target_branch, status = []); end

      sig { params(url: String).returns(Excon::Response) }
      def get(url); end

      sig { params(repo: String, previous_tag: String, new_tag: String).returns(T::Array[T::Hash[String, T.untyped]]) }
      def compare(repo, previous_tag, new_tag); end

      sig { params(repo: String).returns(T::Array[T::Hash[String, String]]) }
      def default_reviewers(repo); end
    end
  end
end
