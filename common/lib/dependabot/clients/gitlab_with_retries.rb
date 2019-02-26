# frozen_string_literal: true

require "gitlab"

module Dependabot
  module Clients
    class GitlabWithRetries
      RETRYABLE_ERRORS = [
        Gitlab::Error::BadGateway
      ].freeze

      #######################
      # Constructor methods #
      #######################

      def self.for_source(source:, credentials:)
        access_token =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == source.hostname }&.
          fetch("password")

        new(
          endpoint: source.api_endpoint,
          private_token: access_token || ""
        )
      end

      def self.for_gitlab_dot_com(credentials:)
        access_token =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == "gitlab.com" }&.
          fetch("password")

        new(
          endpoint: "https://gitlab.com/api/v4",
          private_token: access_token || ""
        )
      end

      #################
      # VCS Interface #
      #################

      def fetch_commit(repo, branch)
        branch(repo, branch).commit.id
      end

      def fetch_default_branch(repo)
        project(repo).default_branch
      end

      ############
      # Proxying #
      ############

      def initialize(max_retries: 3, **args)
        @max_retries = max_retries || 3
        @client = ::Gitlab::Client.new(args)
      end

      def method_missing(method_name, *args, &block)
        retry_connection_failures do
          if @client.respond_to?(method_name)
            mutatable_args = args.map(&:dup)
            @client.public_send(method_name, *mutatable_args, &block)
          else
            super
          end
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @client.respond_to?(method_name) || super
      end

      def retry_connection_failures
        retry_attempt = 0

        begin
          yield
        rescue *RETRYABLE_ERRORS
          retry_attempt += 1
          retry_attempt <= @max_retries ? retry : raise
        end
      end
    end
  end
end
