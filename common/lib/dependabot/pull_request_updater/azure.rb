# frozen_string_literal: true

require "dependabot/clients/azure"
require "securerandom"

module Dependabot
  class PullRequestUpdater
    class Azure
      class PullRequestUpdateFailed < Dependabot::DependabotError; end

      OBJECT_ID_FOR_BRANCH_DELETE = "0000000000000000000000000000000000000000"

      attr_reader :source, :files, :base_commit, :old_commit, :credentials,
                  :pull_request_number, :author_details

      def initialize(source:, files:, base_commit:, old_commit:,
                     credentials:, pull_request_number:, author_details: nil)
        @source = source
        @files = files
        @base_commit = base_commit
        @old_commit = old_commit
        @credentials = credentials
        @pull_request_number = pull_request_number
        @author_details = author_details
      end

      def update
        return unless pull_request_exists? && source_branch_exists?

        update_source_branch
      end

      private

      def azure_client_for_source
        @azure_client_for_source ||=
          Dependabot::Clients::Azure.for_source(
            source: source,
            credentials: credentials
          )
      end

      def pull_request_exists?
        pull_request
      rescue Dependabot::Clients::Azure::NotFound
        false
      end

      def source_branch_exists?
        azure_client_for_source.branch(source_branch_name)
      rescue Dependabot::Clients::Azure::NotFound
        false
      end

      # Currently the PR diff in ADO shows difference in commits instead of actual diff in files.
      # This workaround is done to get the target branch commit history on the source branch alongwith file changes
      def update_source_branch
        # 1) Push the file changes to a newly created temporary branch (from base commit)
        new_commit = create_temp_branch
        # 2) Update PR source branch to point to the temp branch head commit.
        response = update_branch(source_branch_name, old_source_branch_commit, new_commit)
        # 3) Delete temp branch
        update_branch(temp_branch_name, new_commit, OBJECT_ID_FOR_BRANCH_DELETE)

        raise PullRequestUpdateFailed, response.fetch("customMessage", nil) unless response.fetch("success", false)
      end

      def pull_request
        @pull_request ||=
          azure_client_for_source.pull_request(pull_request_number.to_s)
      end

      def source_branch_name
        @source_branch_name ||= pull_request&.fetch("sourceRefName")&.gsub("refs/heads/", "")
      end

      def create_temp_branch
        author = author_details&.slice(:name, :email, :date)
        author = nil unless author&.any?

        response = azure_client_for_source.create_commit(
          temp_branch_name,
          base_commit,
          commit_message,
          files,
          author
        )

        JSON.parse(response.body).fetch("refUpdates").first.fetch("newObjectId")
      end

      def temp_branch_name
        @temp_branch_name ||=
          "#{source_branch_name}-temp-#{SecureRandom.uuid[0..6]}"
      end

      def update_branch(branch_name, old_commit, new_commit)
        azure_client_for_source.update_ref(
          branch_name,
          old_commit,
          new_commit
        )
      end

      # For updating source branch, we require the latest commit for the source branch.
      def commit_being_updated
        @commit_being_updated ||=
          azure_client_for_source.commits(source_branch_name).first
      end

      def old_source_branch_commit
        commit_being_updated.fetch("commitId")
      end

      def commit_message
        commit_being_updated.fetch("comment")
      end
    end
  end
end
