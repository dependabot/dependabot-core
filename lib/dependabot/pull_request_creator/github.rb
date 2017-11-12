# frozen_string_literal: true

require "octokit"

module Dependabot
  class PullRequestCreator
    class Github
      attr_reader :repo_name, :branch_name, :base_commit, :github_client,
                  :files, :pr_description, :pr_name, :commit_message,
                  :target_branch

      def initialize(repo_name:, branch_name:, base_commit:, github_client:,
                     files:, commit_message:, pr_description:, pr_name:,
                     target_branch:)
        @repo_name      = repo_name
        @branch_name    = branch_name
        @base_commit    = base_commit
        @target_branch  = target_branch
        @github_client  = github_client
        @files          = files
        @commit_message = commit_message
        @pr_description = pr_description
        @pr_name = pr_name
      end

      def create
        return if branch_exists?

        commit = create_commit
        return unless create_branch(commit)

        create_label unless dependencies_label_exists?

        pull_request = create_pull_request

        add_label_to_pull_request(pull_request)

        pull_request
      end

      private

      def branch_exists?
        github_client.ref(repo_name, "heads/#{branch_name}")
        true
      rescue Octokit::NotFound
        false
      end

      def create_commit
        tree = create_tree

        github_client.create_commit(
          repo_name,
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
          repo_name,
          file_trees,
          base_tree: base_commit
        )
      end

      def create_branch(commit)
        github_client.create_ref(
          repo_name,
          "heads/#{branch_name}",
          commit.sha
        )
      rescue Octokit::UnprocessableEntity => error
        # Return quietly in the case of a race
        return nil if error.message.match?(/Reference already exists/)
        raise
      end

      def dependencies_label_exists?
        github_client.
          labels(repo_name, per_page: 100).
          map(&:name).
          include?("dependencies")
      end

      def create_label
        github_client.add_label(repo_name, "dependencies", "0025ff")
      rescue Octokit::UnprocessableEntity => error
        raise unless error.errors.first.fetch(:code) == "already_exists"
      end

      def add_label_to_pull_request(pull_request)
        github_client.add_labels_to_an_issue(
          repo_name,
          pull_request.number,
          ["dependencies"]
        )
      end

      def create_pull_request
        github_client.create_pull_request(
          repo_name,
          target_branch || default_branch,
          branch_name,
          pr_name,
          pr_description
        )
      end

      def default_branch
        @default_branch ||= github_client.repository(repo_name).default_branch
      end
    end
  end
end
