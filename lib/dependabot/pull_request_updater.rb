# frozen_string_literal: true

require "octokit"

module Dependabot
  class PullRequestUpdater
    attr_reader :watched_repo, :files, :base_commit, :github_client,
                :pull_request_number

    def initialize(repo:, base_commit:, files:, github_client:,
                   pull_request_number:)
      @watched_repo = repo
      @base_commit = base_commit
      @files = files
      @github_client = github_client
      @pull_request_number = pull_request_number
    end

    def update
      return unless branch_exists?

      commit = create_commit
      update_branch(commit)
    end

    private

    def pull_request
      @pull_request ||=
        github_client.pull_request(watched_repo, pull_request_number)
    end

    def pull_request_exists?
      !pull_request.nil?
    rescue Octokit::NotFound
      false
    end

    def branch_exists?
      github_client.branch(watched_repo, pull_request.head.ref)
    rescue Octokit::NotFound
      false
    end

    def create_commit
      tree = create_tree

      github_client.create_commit(
        watched_repo,
        commit_message,
        tree.sha,
        base_commit
      )
    end

    def create_tree
      file_trees = files.map do |file|
        if file.type == "file"
          {
            path: file.path.sub(%r{^/}, ""),
            mode: "100644",
            type: "blob",
            content: file.content
          }
        elsif file.type == "submodule"
          {
            path: file.path.sub(%r{^/}, ""),
            mode: "160000",
            type: "commit",
            sha: file.content
          }
        else
          raise "Unknown file type #{file.type}"
        end
      end

      github_client.create_tree(
        watched_repo,
        file_trees,
        base_tree: base_commit
      )
    end

    def update_branch(commit)
      github_client.update_ref(
        watched_repo,
        "heads/" + pull_request.head.ref,
        commit.sha,
        true
      )
    rescue Octokit::UnprocessableEntity => error
      # Return quietly if the branch has been deleted
      return nil if error.message =~ /Reference does not exist/
      raise
    end

    def commit_message
      github_client.git_commit(watched_repo, pull_request.head.sha).message
    end
  end
end
