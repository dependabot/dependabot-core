# frozen_string_literal: true

require "gitlab"

module Dependabot
  module Clients
    class Gitlab
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

      def initialize(**args)
        @client = ::Gitlab::Client.new(args)
      end

      def method_missing(method_name, *args, &block)
        if @client.respond_to?(method_name)
          mutatable_args = args.map(&:dup)
          @client.public_send(method_name, *mutatable_args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @client.respond_to?(method_name) || super
      end
    end
  end
end
