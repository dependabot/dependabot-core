# typed: strict
# frozen_string_literal: true

require "octokit"
require "sorbet-runtime"
require "delegate"
require "dependabot/credential"

module Dependabot
  module Clients
    class GithubWithRetries < SimpleDelegator
      extend T::Sig

      DEFAULT_OPEN_TIMEOUT_IN_SECONDS = 2
      DEFAULT_READ_TIMEOUT_IN_SECONDS = 5
      ClientOptions = T.type_alias { T::Hash[Symbol, Object] }

      sig { returns(Integer) }
      def self.open_timeout_in_seconds
        ENV.fetch("DEPENDABOT_OPEN_TIMEOUT_IN_SECONDS", DEFAULT_OPEN_TIMEOUT_IN_SECONDS).to_i
      end

      sig { returns(Integer) }
      def self.read_timeout_in_seconds
        ENV.fetch("DEPENDABOT_READ_TIMEOUT_IN_SECONDS", DEFAULT_READ_TIMEOUT_IN_SECONDS).to_i
      end

      DEFAULT_CLIENT_ARGS = T.let(
        {
          connection_options: {
            request: {
              open_timeout: open_timeout_in_seconds,
              timeout: read_timeout_in_seconds
            }
          }
        }.freeze,
        ClientOptions
      )

      RETRYABLE_ERRORS = T.let(
        [
          Faraday::ConnectionFailed,
          Faraday::TimeoutError,
          Octokit::InternalServerError,
          Octokit::BadGateway
        ].freeze,
        T::Array[T.class_of(StandardError)]
      )

      #######################
      # Constructor methods #
      #######################

      sig do
        params(
          source: Dependabot::Source,
          credentials: T::Array[Dependabot::Credential]
        )
          .returns(Dependabot::Clients::GithubWithRetries)
      end
      def self.for_source(source:, credentials:)
        access_tokens =
          credentials
          .select { |cred| cred["type"] == "git_source" }
          .select { |cred| cred["host"] == source.hostname }
          .select { |cred| cred["password"] }
          .map { |cred| cred.fetch("password") }

        new(
          access_tokens: access_tokens,
          api_endpoint: source.api_endpoint
        )
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(Dependabot::Clients::GithubWithRetries) }
      def self.for_github_dot_com(credentials:)
        access_tokens =
          credentials
          .select { |cred| cred["type"] == "git_source" }
          .select { |cred| cred["host"] == "github.com" }
          .select { |cred| cred["password"] }
          .map { |cred| cred.fetch("password") }

        new(access_tokens: access_tokens)
      end

      #################
      # VCS Interface #
      #################

      sig { params(repo: String, branch: String).returns(String) }
      def fetch_commit(repo, branch)
        response = ref(repo, "heads/#{branch}")

        Kernel.raise Octokit::NotFound if response.is_a?(Array)

        object = T.cast(response[:object], Sawyer::Resource)
        T.cast(object[:sha], String)
      end

      sig { params(repo: String).returns(String) }
      def fetch_default_branch(repo)
        T.cast(repository(repo)[:default_branch], String)
      end

      sig { params(repo: String, path: String, ref: String).returns(String) }
      def raw_contents(repo, path:, ref:)
        T.cast(
          contents(repo, path: path, ref: ref, accept: "application/vnd.github.v3.raw"),
          String
        )
      end

      ############
      # Proxying #
      ############

      sig { params(max_retries: T.nilable(Integer), args: Object).void }
      def initialize(max_retries: 3, **args)
        args = DEFAULT_CLIENT_ARGS.merge(args)
        access_tokens = extract_access_tokens(args)

        # Explicitly set the proxy if one is set in the environment
        # as Faraday's find_proxy is very slow.
        Octokit.configure do |c|
          c.proxy = ENV["HTTPS_PROXY"] if ENV["HTTPS_PROXY"]
        end

        args[:middleware] = Faraday::RackBuilder.new do |builder|
          builder.use Faraday::Retry::Middleware, exceptions: RETRYABLE_ERRORS, max: max_retries || 3

          Octokit::Default::MIDDLEWARE.handlers.each do |handler|
            next if handler.klass == Faraday::Retry::Middleware

            builder.use handler.klass
          end
        end

        @clients = T.let(
          access_tokens.map do |token|
            Octokit::Client.new(args.merge(access_token: token))
          end,
          T::Array[Octokit::Client]
        )
        super(T.must(@clients.last))
      end

      # TODO: Create all the methods that are called on the client
      sig do
        params(
          method_name: T.any(Symbol, String),
          args: Object,
          block: T.nilable(Proc)
        )
          .returns(T.anything)
      end
      def method_missing(method_name, *args, &block)
        original_args = args
        untried_clients = @clients.dup
        client = untried_clients.pop

        begin
          __setobj__(T.must(client))
          args = original_args.map(&:dup)
          super
        rescue Octokit::NotFound, Octokit::Unauthorized, Octokit::Forbidden
          Kernel.raise unless (client = untried_clients.pop)

          retry
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
        @clients.first.respond_to?(method_name, include_private)
      end

      private

      sig { params(args: ClientOptions).returns(T::Array[T.nilable(String)]) }
      def extract_access_tokens(args)
        access_tokens = T.let([], T::Array[T.nilable(String)])
        case (raw_access_tokens = args.delete(:access_tokens))
        when nil
          nil
        when Array
          raw_access_tokens.each do |raw_token|
            token = T.cast(raw_token, Object)
            case token
            when nil, String then access_tokens << token
            else Kernel.raise TypeError, "access_tokens must contain only strings or nil"
            end
          end
        else
          Kernel.raise TypeError, "access_tokens must be an array or nil"
        end

        access_token = args[:access_token]
        case access_token
        when nil
          nil
        when String
          access_tokens << access_token
        else
          Kernel.raise TypeError, "access_token must be a string or nil"
        end

        access_tokens << nil if access_tokens.empty?
        access_tokens.uniq
      end
    end
  end
end
