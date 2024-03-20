# typed: strict
# frozen_string_literal: true

require_relative "bitbucket"

module Dependabot
  module Clients
    class BitbucketWithRetries
      extend T::Sig

      RETRYABLE_ERRORS = T.let(
        [Excon::Error::Timeout, Excon::Error::Socket].freeze,
        T::Array[T.class_of(Excon::Error)]
      )

      #######################
      # Constructor methods #
      #######################

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(BitbucketWithRetries) }
      def self.for_bitbucket_dot_org(credentials:)
        credential =
          credentials
          .select { |cred| cred["type"] == "git_source" }
          .find { |cred| cred["host"] == "bitbucket.org" }

        new(credentials: credential)
      end

      ############
      # Proxying #
      ############

      sig { params(credentials: T.nilable(Dependabot::Credential), max_retries: T.nilable(Integer)).void }
      def initialize(credentials:, max_retries: 3)
        @max_retries = T.let(max_retries || 3, Integer)
        @client = T.let(Bitbucket.new(credentials: credentials), Dependabot::Clients::Bitbucket)
      end

      sig do
        params(
          method_name: T.any(Symbol, String),
          args: T.untyped,
          block: T.nilable(T.proc.returns(T.untyped))
        )
          .returns(T.untyped)
      end
      def method_missing(method_name, *args, &block)
        retry_connection_failures do
          if @client.respond_to?(method_name)
            mutatable_args = args.map(&:dup)
            T.unsafe(@client).public_send(method_name, *mutatable_args, &block)
          else
            super
          end
        end
      end

      sig do
        params(
          method_name: Symbol,
          include_private: T::Boolean
        )
          .returns(T::Boolean)
      end
      def respond_to_missing?(method_name, include_private = false)
        @client.respond_to?(method_name) || super
      end

      sig do
        type_parameters(:T)
          .params(_blk: T.proc.returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      def retry_connection_failures(&_blk)
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
