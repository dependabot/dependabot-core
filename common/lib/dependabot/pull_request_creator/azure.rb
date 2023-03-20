# frozen_string_literal: true

require "dependabot/clients/azure"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class Azure
      attr_reader :source, :branch_name, :base_commit, :credentials,
                  :files, :commit_message, :pr_description, :pr_name,
                  :author_details, :labeler, :reviewers, :assignees, :work_item

      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     author_details:, labeler:, reviewers: nil, assignees: nil, work_item: nil)
        @source         = source
        @branch_name    = branch_name
        @base_commit    = base_commit
        @credentials    = credentials
        @files          = files
        @commit_message = commit_message
        @pr_description = pr_description
        @pr_name        = pr_name
        @author_details = author_details
        @labeler        = labeler
        @reviewers      = reviewers
        @assignees      = assignees
        @work_item      = work_item
      end

      def create
        return if branch_exists? && pull_request_exists?

        # For Azure we create or update a branch in the same request as creating
        # a commit (so we don't need create or update branch logic here)
        create_commit

        create_pull_request
      end

      private

      def azure_client_for_source
        @azure_client_for_source ||=
          Dependabot::Clients::Azure.for_source(
            source: source,
            credentials: credentials
          )
      end

      def branch_exists?
        azure_client_for_source.branch(branch_name)
      rescue ::Azure::Error::NotFound
        false
      end

      def pull_request_exists?
        azure_client_for_source.pull_requests(
          branch_name,
          source.branch || default_branch
        ).any?
      end

      def create_commit
        author = author_details&.slice(:name, :email, :date)
        author = nil unless author&.any?

        azure_client_for_source.create_commit(
          branch_name,
          base_commit,
          commit_message,
          files,
          author
        )
      end

      def create_pull_request
        azure_client_for_source.create_pull_request(
          pr_name,
          branch_name,
          source.branch || default_branch,
          pr_description,
          labeler.labels_for_pr,
          reviewers,
          assignees,
          work_item
        )
      end

      def default_branch
        @default_branch ||=
          azure_client_for_source.fetch_default_branch(source.repo)
      end
    end
  end
end
