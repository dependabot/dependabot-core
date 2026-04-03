# typed: strong
# frozen_string_literal: true

# Method signatures for Gitlab::Client methods delegated via method_missing.
# These allow callers to use GitlabWithRetries without T.unsafe wrappers.

module Dependabot
  module Clients
    class GitlabWithRetries
      # Branches
      sig { params(project: String, branch: String).returns(Gitlab::ObjectifiedHash) }
      def branch(project, branch); end

      # Commits
      sig { params(project: String, options: T.untyped).returns(Gitlab::PaginatedResponse) }
      def commits(project, options = {}); end

      sig { params(project: String, sha: String).returns(Gitlab::ObjectifiedHash) }
      def commit(project, sha); end

      # Merge requests
      sig { params(project: String, options: T.untyped).returns(Gitlab::PaginatedResponse) }
      def merge_requests(project, options = {}); end

      sig { params(project: String, id: Integer, options: T.untyped).returns(Gitlab::ObjectifiedHash) }
      def merge_request(project, id, options = {}); end

      sig { params(project: String, title: String, options: T.untyped).returns(Gitlab::ObjectifiedHash) }
      def create_merge_request(project, title, options = {}); end

      sig do
        params(
          project: String,
          merge_request: Integer,
          options: T.untyped
        ).returns(Gitlab::ObjectifiedHash)
      end
      def create_merge_request_level_rule(project, merge_request, options = {}); end

      # Branches
      sig { params(project: String, branch: String, ref: String).returns(Gitlab::ObjectifiedHash) }
      def create_branch(project, branch, ref); end

      # Projects
      sig { params(id: String, options: T.untyped).returns(Gitlab::ObjectifiedHash) }
      def project(id, options = {}); end

      # Repository files
      sig { params(project: String, file_path: String, ref: String).returns(Gitlab::ObjectifiedHash) }
      def get_file(project, file_path, ref); end

      sig { params(project: String, options: T.untyped).returns(Gitlab::PaginatedResponse) }
      def repo_tree(project, options = {}); end

      sig { params(project: String, submodule: String, options: T.untyped).returns(Gitlab::ObjectifiedHash) }
      def edit_submodule(project, submodule, options = {}); end

      # Labels
      sig do
        params(
          project: String,
          name: String,
          color: String,
          options: T.untyped
        ).returns(Gitlab::ObjectifiedHash)
      end
      def create_label(project, name, color, options = {}); end

      sig { params(project: String, options: T.untyped).returns(Gitlab::PaginatedResponse) }
      def labels(project, options = {}); end

      # Tags
      sig { params(project: String, options: T.untyped).returns(Gitlab::PaginatedResponse) }
      def tags(project, options = {}); end

      # Comparison
      sig { params(project: String, from: String, to: String).returns(Gitlab::ObjectifiedHash) }
      def compare(project, from, to); end
    end
  end
end
