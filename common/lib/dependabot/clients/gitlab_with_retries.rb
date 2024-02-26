# typed: strict
# frozen_string_literal: true

require "gitlab"
require "sorbet-runtime"

require "dependabot/credential"

module Dependabot
  module Clients
    class GitlabWithRetries
      extend T::Sig

      RETRYABLE_ERRORS = T.let(
        [Gitlab::Error::BadGateway].freeze,
        T::Array[T.class_of(Gitlab::Error::ResponseError)]
      )

      class ContentEncoding
        BASE64 = "base64"
        TEXT = "text"
      end

      #######################
      # Constructor methods #
      #######################

      sig do
        params(
          source: Dependabot::Source,
          credentials: T::Array[Dependabot::Credential]
        )
          .returns(Dependabot::Clients::GitlabWithRetries)
      end
      def self.for_source(source:, credentials:)
        access_token =
          credentials
          .select { |cred| cred["type"] == "git_source" }
          .select { |cred| cred["password"] }
          .find { |cred| cred["host"] == source.hostname }
          &.fetch("password")

        new(
          endpoint: source.api_endpoint,
          private_token: access_token || ""
        )
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(Dependabot::Clients::GitlabWithRetries) }
      def self.for_gitlab_dot_com(credentials:)
        access_token =
          credentials
          .select { |cred| cred["type"] == "git_source" }
          .select { |cred| cred["password"] }
          .find { |cred| cred["host"] == "gitlab.com" }
          &.fetch("password")

        new(
          endpoint: "https://gitlab.com/api/v4",
          private_token: access_token || ""
        )
      end

      #################
      # VCS Interface #
      #################

      sig { params(repo: String, branch: String).returns(String) }
      def fetch_commit(repo, branch)
        T.unsafe(self).branch(repo, branch).commit.id
      end

      sig { params(repo: String).returns(String) }
      def fetch_default_branch(repo)
        T.unsafe(self).project(repo).default_branch
      end

      ############
      # Proxying #
      ############

      sig { params(max_retries: T.nilable(Integer), args: T.untyped).void }
      def initialize(max_retries: 3, **args)
        @max_retries = T.let(max_retries || 3, Integer)
        @client = T.let(::Gitlab::Client.new(args), ::Gitlab::Client)
      end

      # Create commit in gitlab repo with correctly mapped file actions
      #
      # @param [String] repo
      # @param [String] branch_name
      # @param [String] commit_message
      # @param [Array<Dependabot::DependencyFile>] files
      # @param [Hash] options
      # @return [Gitlab::ObjectifiedHash]
      sig do
        params(
          repo: String,
          branch_name: String,
          commit_message: String,
          files: T::Array[Dependabot::DependencyFile],
          options: T.untyped
        )
          .returns(Gitlab::ObjectifiedHash)
      end
      def create_commit(repo, branch_name, commit_message, files, **options)
        @client.create_commit(
          repo,
          branch_name,
          commit_message,
          file_actions(files),
          options
        )
      end

      # TODO: Create all the methods that are called on the client
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

      private

      # Array of file actions for a commit
      #
      # @param [Array<Dependabot::DependencyFile>] files
      # @return [Array<Hash>]
      sig { params(files: T::Array[Dependabot::DependencyFile]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def file_actions(files)
        files.map do |file|
          {
            action: file_action(file),
            encoding: file_encoding(file),
            file_path: file.type == "symlink" ? file.symlink_target : file.path,
            content: file.content
          }
        end
      end

      # Single file action
      #
      # @param [Dependabot::DependencyFile] file
      # @return [String]
      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def file_action(file)
        if file.operation == Dependabot::DependencyFile::Operation::DELETE
          "delete"
        elsif file.operation == Dependabot::DependencyFile::Operation::CREATE
          "create"
        else
          "update"
        end
      end

      # Encoding option for gitlab commit operation
      #
      # @param [Dependabot::DependencyFile] file
      # @return [String]
      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def file_encoding(file)
        return ContentEncoding::BASE64 if file.content_encoding == Dependabot::DependencyFile::ContentEncoding::BASE64

        ContentEncoding::TEXT
      end
    end
  end
end
