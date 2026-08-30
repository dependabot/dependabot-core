# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"

require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator"
require "dependabot/source"

module Dependabot
  module DryRun
    class PullRequestMode
      extend T::Sig

      class Evidence < T::Struct
        extend T::Sig

        const :number, Integer
        const :url, String

        sig { returns(String) }
        def message
          "Pull request ##{number} created successfully: #{url}"
        end
      end

      AUTHOR_DETAILS = T.let(
        {
          name: "dependabot[bot]",
          email: "49699333+dependabot[bot]@users.noreply.github.com"
        }.freeze,
        T::Hash[Symbol, String]
      )
      GITHUB_DOT_COM_API_ENDPOINT = "https://api.github.com/"

      sig do
        params(
          source: Dependabot::Source,
          credentials: T::Array[Dependabot::Credential],
          dependency_names: T.nilable(T::Array[String]),
          cache_steps: T::Array[String]
        ).void
      end
      def initialize(source:, credentials:, dependency_names:, cache_steps:)
        @source = source
        @credentials = credentials
        @dependency_names = dependency_names
        @cache_steps = cache_steps
        @created = T.let(false, T::Boolean)
      end

      sig { void }
      def validate!
        unless source.provider == "github"
          raise ArgumentError, "--create-pull-request supports only the github provider"
        end
        unless source.hostname.casecmp?("github.com") && source.api_endpoint == GITHUB_DOT_COM_API_ENDPOINT
          raise ArgumentError, "--create-pull-request supports only github.com"
        end
        unless dependency_names&.one?
          raise ArgumentError, "--create-pull-request requires exactly one dependency through --dep"
        end
        raise ArgumentError, "--create-pull-request cannot be combined with --cache" if cache_steps.any?
        return if source_credential?

        raise ArgumentError,
              "--create-pull-request requires a git_source credential for #{source.hostname}"
      end

      sig { params(dependencies: T::Array[Dependabot::Dependency]).void }
      def validate_dependency_selection!(dependencies)
        return if dependencies.one?

        raise ArgumentError,
              "--create-pull-request requires exactly one matching parsed dependency"
      end

      sig { params(files: T::Array[Dependabot::DependencyFile]).void }
      def validate_dependency_files!(files)
        return if files.any?

        raise "--create-pull-request requires fetched dependency files"
      end

      sig { returns(T::Boolean) }
      def created?
        @created
      end

      sig do
        params(
          base_commit: T.nilable(String),
          dependencies: T::Array[Dependabot::Dependency],
          files: T::Array[Dependabot::DependencyFile],
          message: Dependabot::PullRequestCreator::Message,
          commit_message_options: T::Hash[Symbol, T.anything]
        ).returns(Evidence)
      end
      def create(base_commit:, dependencies:, files:, message:, commit_message_options:)
        validate!
        raise ArgumentError, "--create-pull-request creates at most one pull request" if created?
        raise ArgumentError, "--create-pull-request requires a resolved base commit" if base_commit.to_s.empty?
        raise ArgumentError, "--create-pull-request requires updated dependency files" if files.empty?

        raw_pull_request = Dependabot::PullRequestCreator.new(
          source: source,
          base_commit: T.must(base_commit),
          dependencies: dependencies,
          files: files,
          credentials: credentials,
          message: message,
          commit_message_options: commit_message_options,
          author_details: AUTHOR_DETAILS,
          label_language: true,
          require_up_to_date_base: true
        ).create

        evidence = pull_request_evidence(T.cast(raw_pull_request, Object))

        @created = true
        evidence
      end

      private

      sig { returns(Dependabot::Source) }
      attr_reader :source

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :dependency_names

      sig { returns(T::Array[String]) }
      attr_reader :cache_steps

      sig { returns(T::Boolean) }
      def source_credential?
        credentials.any? do |credential|
          credential["type"] == "git_source" &&
            credential["host"] == source.hostname &&
            !credential["password"].to_s.strip.empty?
        end
      end

      sig { params(pull_request: Object).returns(Evidence) }
      def pull_request_evidence(pull_request)
        raise invalid_pull_request_result unless pull_request.is_a?(Sawyer::Resource)

        url = pull_request_url(pull_request)
        number = pull_request_number(pull_request)
        raise invalid_pull_request_result unless valid_pull_request_url?(url, number)

        Evidence.new(number: number, url: url)
      end

      sig { params(pull_request: Sawyer::Resource).returns(String) }
      def pull_request_url(pull_request)
        url = T.cast(pull_request[:html_url], Object)
        raise invalid_pull_request_result unless url.is_a?(String)

        url
      end

      sig { params(pull_request: Sawyer::Resource).returns(Integer) }
      def pull_request_number(pull_request)
        number = T.cast(pull_request[:number], Object)
        raise invalid_pull_request_result unless number.is_a?(Integer) && number.positive?

        number
      end

      sig { params(url: String, number: Integer).returns(T::Boolean) }
      def valid_pull_request_url?(url, number)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTPS) &&
          valid_github_origin?(uri) &&
          valid_pull_request_path?(uri.path, number) &&
          uri.query.nil? &&
          uri.fragment.nil? &&
          uri.userinfo.nil?
      rescue URI::InvalidURIError
        false
      end

      sig { params(uri: URI::HTTPS).returns(T::Boolean) }
      def valid_github_origin?(uri)
        uri.host&.casecmp?("github.com") == true && uri.port == 443
      end

      sig { params(path: String, number: Integer).returns(T::Boolean) }
      def valid_pull_request_path?(path, number)
        segments = path.split("/", -1)
        return false unless segments.length == 5

        source_owner, source_repo = source.repo.split("/", 2)

        segments[0] == "" &&
          segments[1]&.casecmp?(source_owner) == true &&
          segments[2]&.casecmp?(source_repo) == true &&
          segments[3] == "pull" &&
          segments[4] == number.to_s
      end

      sig { returns(RuntimeError) }
      def invalid_pull_request_result
        RuntimeError.new("Pull request creation did not return a usable GitHub pull request URL")
      end
    end
  end
end
