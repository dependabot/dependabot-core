# frozen_string_literal: true

require "gitlab"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class Gitlab
      attr_reader :source, :branch_name, :base_commit, :credentials,
                  :files, :pr_description, :pr_name, :commit_message,
                  :target_branch, :author_details, :custom_labels

      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     target_branch:, author_details:, custom_labels:)
        @source         = source
        @branch_name    = branch_name
        @base_commit    = base_commit
        @target_branch  = target_branch
        @credentials    = credentials
        @files          = files
        @commit_message = commit_message
        @pr_description = pr_description
        @pr_name        = pr_name
        @author_details = author_details
        @custom_labels  = custom_labels
      end

      def create
        return if branch_exists? && merge_request_exists?

        create_branch unless branch_exists?
        create_commit
        create_label unless custom_labels || dependencies_label_exists?
        create_merge_request
      end

      private

      def gitlab_client_for_source
        access_token =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == source.hostname }&.
          fetch("password")

        @gitlab_client_for_source ||=
          ::Gitlab.client(
            endpoint: "https://gitlab.com/api/v4",
            private_token: access_token || ""
          )
      end

      def branch_exists?
        @branch_ref ||=
          gitlab_client_for_source.branch(source.repo, branch_name)
        true
      rescue ::Gitlab::Error::NotFound
        false
      end

      def merge_request_exists?
        gitlab_client_for_source.merge_requests(
          source.repo,
          source_branch: branch_name,
          target_branch: target_branch || default_branch,
          state: "all"
        ).any?
      end

      def create_branch
        gitlab_client_for_source.create_branch(
          source.repo,
          branch_name,
          base_commit
        )
      end

      def create_commit
        # TODO: Handle submodule updates on GitLab
        # (see https://gitlab.com/gitlab-org/gitlab-ce/issues/41213)
        actions = files.map do |file|
          {
            action: "update",
            file_path: file.path,
            content: file.content
          }
        end

        gitlab_client_for_source.create_commit(
          source.repo,
          branch_name,
          commit_message,
          actions
        )
      end

      def dependencies_label_exists?
        return (custom_labels - labels).empty? if custom_labels

        labels.any? { |l| l.match?(/dependenc/i) }
      end

      def labels
        @labels ||=
          gitlab_client_for_source.
          labels(source.repo).
          map(&:name)
      end

      def create_label
        gitlab_client_for_source.create_label(
          source.repo, "dependencies", "#0025ff"
        )
        @labels = [*@labels, "dependencies"].uniq
      end

      def create_merge_request
        label_names =
          custom_labels ||
          [labels.find { |l| l.match?(/dependenc/i) }]

        gitlab_client_for_source.create_merge_request(
          source.repo,
          pr_name,
          source_branch: branch_name,
          target_branch: target_branch || default_branch,
          description: pr_description,
          remove_source_branch: true,
          labels: label_names.join(",")
        )
      end

      def default_branch
        @default_branch ||=
          gitlab_client_for_source.project(source.repo).default_branch
      end
    end
  end
end
