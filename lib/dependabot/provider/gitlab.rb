# frozen_string_literal: true

module Dependabot
  class Provider
    class Gitlab

      def commit(repo, branch, gitlab_client)
        gitlab_client.branch(repo, branch).commit.id
      end

      def default_branch_for_repo(repo, gitlab_client)
        gitlab_client.project(repo).default_branch
      end
    end
  end
end
