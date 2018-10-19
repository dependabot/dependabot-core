# frozen_string_literal: true

module Dependabot
  class Provider
    class Github

      def commit(repo, github_client_for_source)
        github_client_for_source.ref(repo, "heads/#{branch}").object.sha
      end

      def default_branch_for_repo(repo, github_client_for_source)
        github_client_for_source.repository(repo).default_branch
      end
    end
  end
end
