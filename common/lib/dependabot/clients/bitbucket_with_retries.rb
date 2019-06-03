# frozen_string_literal: true

require_relative "bitbucket"

module Dependabot
  module Clients
    class BitbucketWithRetries
      RETRYABLE_ERRORS = [
        Excon::Error::Timeout,
        Excon::Error::Socket
      ].freeze

      #######################
      # Constructor methods #
      #######################

      def self.for_bitbucket_dot_org(credentials:)
        credential =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == "bitbucket.org" }

        new(credentials: credential)
      end

      ############
      # Proxying #
      ############

      def initialize(max_retries: 3, **args)
        @max_retries = max_retries || 3
        @client = Bitbucket.new(args)
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

      # rubocop:disable Naming/RescuedExceptionsVariableName
      def retry_connection_failures
        retry_attempt = 0

        begin
          yield
        rescue *RETRYABLE_ERRORS
          retry_attempt += 1
          retry_attempt <= @max_retries ? retry : raise
        end
      end
      # rubocop:enable Naming/RescuedExceptionsVariableName
    end
  end
end
