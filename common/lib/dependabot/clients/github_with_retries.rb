# frozen_string_literal: true

require "octokit"

module Dependabot
  module Clients
    class GithubWithRetries
      OPEN_TIMEOUT_IN_SECONDS = ENV["OPEN_TIMEOUT_IN_SECONDS"] || 2
      DEFAULT_CLIENT_ARGS = {
        connection_options: {
          request: {
            open_timeout: OPEN_TIMEOUT_IN_SECONDS.to_i,
            timeout: 5
          }
        }
      }.freeze

      RETRYABLE_ERRORS = [
        Faraday::ConnectionFailed,
        Faraday::TimeoutError,
        Octokit::InternalServerError,
        Octokit::BadGateway
      ].freeze

      #######################
      # Constructor methods #
      #######################

      def self.for_source(source:, credentials:)
        access_tokens =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          select { |cred| cred["host"] == source.hostname }.
          select { |cred| cred["password"] }.
          map { |cred| cred.fetch("password") }

        new(
          access_tokens: access_tokens,
          api_endpoint: source.api_endpoint
        )
      end

      def self.for_github_dot_com(credentials:)
        access_tokens =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          select { |cred| cred["host"] == "github.com" }.
          select { |cred| cred["password"] }.
          map { |cred| cred.fetch("password") }

        new(access_tokens: access_tokens)
      end

      #################
      # VCS Interface #
      #################

      def fetch_commit(repo, branch)
        response = ref(repo, "heads/#{branch}")

        raise Octokit::NotFound if response.is_a?(Array)

        response.object.sha
      end

      def fetch_default_branch(repo)
        repository(repo).default_branch
      end

      ############
      # Proxying #
      ############

      def initialize(max_retries: 3, **args)
        args = DEFAULT_CLIENT_ARGS.merge(args)

        access_tokens = args.delete(:access_tokens) || []
        access_tokens << args[:access_token] if args[:access_token]
        access_tokens << nil if access_tokens.empty?
        access_tokens.uniq!

        @max_retries = max_retries || 3
        @clients = access_tokens.map do |token|
          Octokit::Client.new(args.merge(access_token: token))
        end
      end

      def method_missing(method_name, *args, &block)
        untried_clients = @clients.dup
        client = untried_clients.pop

        begin
          retry_connection_failures do
            if client.respond_to?(method_name)
              mutatable_args = args.map(&:dup)
              client.public_send(method_name, *mutatable_args, &block)
            else
              super
            end
          end
        rescue Octokit::NotFound, Octokit::Unauthorized, Octokit::Forbidden
          raise unless (client = untried_clients.pop)

          retry
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @clients.first.respond_to?(method_name) || super
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
