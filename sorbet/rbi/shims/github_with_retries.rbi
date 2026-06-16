# typed: strong
# frozen_string_literal: true

# Method signatures for Octokit::Client methods delegated via method_missing.
# These allow callers to use GithubWithRetries without T.unsafe wrappers.

module Dependabot
  module Clients
    class GithubWithRetries
      # Repositories
      sig { params(repo: String, options: T.untyped).returns(Sawyer::Resource) }
      def repo(repo, options = {}); end

      sig { params(repo: String, options: T.untyped).returns(Sawyer::Resource) }
      def repository(repo, options = {}); end

      # Contents
      sig { params(repo: String, options: T.untyped).returns(T.any(Sawyer::Resource, T::Array[Sawyer::Resource])) }
      def contents(repo, options = {}); end

      # Commits
      sig { params(repo: String, options: T.untyped).returns(T::Array[Sawyer::Resource]) }
      def commits(repo, options = {}); end

      sig do
        params(
          repo: String,
          message: String,
          tree: String,
          parents: T.nilable(T.any(String, T::Array[String])),
          options: T.untyped
        ).returns(Sawyer::Resource)
      end
      def create_commit(repo, message, tree, parents = nil, options = {}); end

      sig do
        params(
          repo: String,
          start: String,
          endd: String,
          options: T.untyped
        ).returns(Sawyer::Resource)
      end
      def compare(repo, start, endd, options = {}); end

      # Git objects
      sig { params(repo: String, blob_sha: String, options: T.untyped).returns(Sawyer::Resource) }
      def blob(repo, blob_sha, options = {}); end

      sig do
        params(
          repo: String,
          content: String,
          encoding: T.nilable(String),
          options: T.untyped
        ).returns(String)
      end
      def create_blob(repo, content, encoding = nil, options = {}); end

      sig { params(repo: String, tree: T.untyped, options: T.untyped).returns(Sawyer::Resource) }
      def create_tree(repo, tree, options = {}); end

      # Refs
      sig { params(repo: String, ref: String, options: T.untyped).returns(Sawyer::Resource) }
      def ref(repo, ref, options = {}); end

      sig do
        params(
          repo: String,
          ref: String,
          sha: String,
          options: T.untyped
        ).returns(Sawyer::Resource)
      end
      def create_ref(repo, ref, sha, options = {}); end

      sig do
        params(
          repo: String,
          ref: String,
          sha: String,
          force: T.nilable(T::Boolean),
          options: T.untyped
        ).returns(Sawyer::Resource)
      end
      def update_ref(repo, ref, sha, force = nil, options = {}); end

      # Branches
      sig { params(repo: String, branch: String, options: T.untyped).returns(Sawyer::Resource) }
      def branch(repo, branch, options = {}); end

      # Pull requests
      sig { params(repo: String, options: T.untyped).returns(T::Array[Sawyer::Resource]) }
      def pull_requests(repo, options = {}); end

      sig { params(repo: String, number: Integer, options: T.untyped).returns(Sawyer::Resource) }
      def pull_request(repo, number, options = {}); end

      sig do
        params(
          repo: String,
          base: String,
          head: String,
          title: String,
          body: T.nilable(String),
          options: T.untyped
        ).returns(Sawyer::Resource)
      end
      def create_pull_request(repo, base, head, title, body = nil, options = {}); end

      sig { params(args: T.untyped).returns(Sawyer::Resource) }
      def update_pull_request(*args); end

      sig do
        params(
          repo: String,
          number: Integer,
          reviewers: T.nilable(T.any(T::Array[String], T::Hash[Symbol, T.untyped])),
          options: T.untyped
        ).returns(Sawyer::Resource)
      end
      def request_pull_request_review(repo, number, reviewers = nil, options = {}); end

      # Issues
      sig { params(repo: String, number: Integer, comment: String, options: T.untyped).returns(Sawyer::Resource) }
      def add_comment(repo, number, comment, options = {}); end

      sig do
        params(
          repo: String,
          number: Integer,
          assignees: T::Array[String],
          options: T.untyped
        ).returns(Sawyer::Resource)
      end
      def add_assignees(repo, number, assignees, options = {}); end

      sig { params(repo: String, number: Integer, args: T.untyped).returns(Sawyer::Resource) }
      def update_issue(repo, number, *args); end

      # Labels
      sig { params(repo: String, per_page: T.untyped, options: T.untyped).returns(T::Array[Sawyer::Resource]) }
      def labels(repo, per_page = nil, options = {}); end

      sig { params(repo: String, number: Integer, labels: T::Array[String]).returns(T::Array[Sawyer::Resource]) }
      def add_labels_to_an_issue(repo, number, labels); end

      sig do
        params(
          repo: String,
          label: String,
          color: String,
          options: T.untyped
        ).returns(Sawyer::Resource)
      end
      def add_label(repo, label, color, options = {}); end

      # Releases
      sig { params(repo: String, options: T.untyped).returns(T::Array[Sawyer::Resource]) }
      def releases(repo, options = {}); end

      # Git data
      sig { params(repo: String, sha: String, options: T.untyped).returns(Sawyer::Resource) }
      def git_commit(repo, sha, options = {}); end

      # Pull request commits
      sig { params(repo: String, number: Integer, options: T.untyped).returns(T::Array[Sawyer::Resource]) }
      def pull_request_commits(repo, number, options = {}); end

      # HTTP
      sig { params(url: String, options: T.untyped).returns(Sawyer::Resource) }
      def get(url, options = {}); end

      # Pagination
      sig { returns(Sawyer::Response) }
      def last_response; end
    end
  end
end
