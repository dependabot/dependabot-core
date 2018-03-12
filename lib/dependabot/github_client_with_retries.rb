# frozen_string_literal: true

require "octokit"

module Dependabot
  class GithubClientWithRetries
    DEFAULT_CLIENT_ARGS = {
      connection_options: {
        request: {
          open_timeout: 2,
          timeout: 5
        }
      }
    }.freeze

    RETRYABLE_ERRORS = [
      Faraday::ConnectionFailed,
      Faraday::TimeoutError,
      Octokit::InternalServerError
    ].freeze

    def initialize(max_retries: 1, **args)
      args = DEFAULT_CLIENT_ARGS.merge(args)

      @max_retries = max_retries || 1
      @client = Octokit::Client.new(**args)
    end

    def method_missing(method_name, *args, &block)
      retry_connection_failures do
        if @client.respond_to?(method_name)
          @client.public_send(method_name, *args, &block)
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
