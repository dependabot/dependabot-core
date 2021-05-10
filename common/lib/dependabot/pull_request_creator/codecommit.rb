# frozen_string_literal: true

require "dependabot/clients/codecommit"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class Codecommit
      attr_reader :source, :branch_name, :base_commit, :credentials,
                  :files, :commit_message, :pr_description, :pr_name,
                  :author_details, :labeler

      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     author_details:, labeler:, require_up_to_date_base:)
        @source                  = source
        @branch_name             = branch_name
        @base_commit             = base_commit
        @credentials             = credentials
        @files                   = files
        @commit_message          = commit_message
        @pr_description          = pr_description
        @pr_name                 = pr_name
        @author_details          = author_details
        @labeler                 = labeler
        @require_up_to_date_base = require_up_to_date_base
      end

      def create
        return if branch_exists?(branch_name) && unmerged_pull_request_exists?
        return if require_up_to_date_base? && !base_commit_is_up_to_date?

        create_pull_request
      end

      private

      def require_up_to_date_base?
        @require_up_to_date_base
      end

      def base_commit_is_up_to_date?
        codecommit_client_for_source.fetch_commit(
          source.repo,
          branch_name
        ) == base_commit
      end

      def create_pull_request
        branch = create_or_get_branch(base_commit)
        return unless branch

        create_commit

        pull_request = codecommit_client_for_source.create_pull_request(
          pr_name,
          branch_name,
          source.branch || default_branch,
          pr_description
          # codecommit doesn't support PR labels
        )
        return unless pull_request

        pull_request
      end

      def create_or_get_branch(commit)
        # returns the branch name
        if branch_exists?(branch_name)
          branch_name
        else
          create_branch(commit)
        end
      end

      def create_branch(commit)
        # codecommit returns an empty response on create branch success
        codecommit_client_for_source.create_branch(source.repo, branch_name,
                                                   commit)
        @branch_name = branch_name
        branch_name
      end

      def codecommit_client_for_source
        @codecommit_client_for_source ||=
          Dependabot::Clients::CodeCommit.for_source(
            source: source,
            credentials: credentials
          )
      end

      def branch_exists?(branch_name)
        @branch_ref ||= codecommit_client_for_source.branch(branch_name)
        rescue Aws::CodeCommit::Errors::BranchDoesNotExistException
          false
      end

      def unmerged_pull_request_exists?
        unmerged_prs = []
        pull_requests_for_branch.each do |pr|
          unless pr.pull_request.
                 pull_request_targets[0].merge_metadata.is_merged
            unmerged_prs << pr
          end
        end
        unmerged_prs.any?
      end

      def pull_requests_for_branch
        @pull_requests_for_branch ||=
          begin
            open_prs = codecommit_client_for_source.pull_requests(
              source.repo,
              "open",
              source.branch || default_branch
            )
            closed_prs = codecommit_client_for_source.pull_requests(
              source.repo,
              "closed",
              source.branch || default_branch
            )

            [*open_prs, *closed_prs]
          end
      end

      def create_commit
        author = author_details&.slice(:name, :email, :date)
        author = nil unless author&.any?

        codecommit_client_for_source.create_commit(
          branch_name,
          author,
          base_commit,
          commit_message,
          files
        )
      end

      def default_branch
        @default_branch ||=
          codecommit_client_for_source.fetch_default_branch(source.repo)
      end
    end
  end
end
