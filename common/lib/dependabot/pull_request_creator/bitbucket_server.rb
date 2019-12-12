# frozen_string_literal: true

require "dependabot/clients/bitbucket_server"

module Dependabot
  class PullRequestCreator
    class BitbucketServer
      attr_reader :source, :branch_name, :base_commit, :credentials,
                  :files, :commit_message, :pr_description, :pr_name,
                  :reviewers

      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     reviewers: nil)
        @source         = source
        @branch_name    = branch_name
        @base_commit    = base_commit
        @credentials    = credentials
        @files          = files
        @commit_message = commit_message
        @pr_description = pr_description
        @pr_name        = pr_name
        @reviewers      = reviewers
      end

      def create
        return if branch_exists? && pull_request_exists?

        if branch_exists?
          create_commit unless commit_exists?
        else
          create_branch
          create_commit
        end

        create_pull_request
      end

      private

      def client_for_source
        @client_for_source ||=
          Dependabot::Clients::BitbucketServer.for_source(
            source: source,
            credentials: credentials
          )
      end

      def branch_exists?
        @branch_exists ||= client_for_source.fetch_branch_by_name(branch_name)
      end

      def create_branch
        client_for_source.create_branch(branch_name, base_commit)
      end

      def pull_request
        @pull_request ||= client_for_source.
                          fetch_pull_request_for_branch(branch_name)
      end

      def pull_request_exists?
        pull_request.nil? ? false : true
      end

      def create_pull_request
        client_for_source.create_pull_request(
          pr_name,
          branch_name,
          target_branch,
          pr_description,
          reviewers
        )
      end

      def commit_exists?
        @commit_exists ||= client_for_source.
                           fetch_commit_message(branch_name) == commit_message
      end

      def create_commit
        client_for_source.create_commit(
          branch_name,
          commit_message,
          files
        )
      end

      def target_branch
        source.branch || default_branch
      end

      def default_branch
        @default_branch ||= client_for_source.fetch_default_branch(nil)
      end
    end
  end
end
