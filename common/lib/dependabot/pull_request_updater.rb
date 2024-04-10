# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pull_request_updater/github"
require "dependabot/pull_request_updater/gitlab"
require "dependabot/pull_request_updater/azure"
require "dependabot/credential"

module Dependabot
  class PullRequestUpdater
    extend T::Sig

    class BranchProtected < StandardError; end

    sig { returns(Dependabot::Source) }
    attr_reader :source

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    attr_reader :files

    sig { returns(String) }
    attr_reader :base_commit

    sig { returns(String) }
    attr_reader :old_commit

    sig { returns(T::Array[Dependabot::Credential]) }
    attr_reader :credentials

    sig { returns(Integer) }
    attr_reader :pull_request_number

    sig { returns(T.nilable(T::Hash[Symbol, String])) }
    attr_reader :author_details

    sig { returns(T.nilable(String)) }
    attr_reader :signature_key

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :provider_metadata

    sig do
      params(
        source: Dependabot::Source,
        base_commit: String,
        old_commit: String,
        files: T::Array[Dependabot::DependencyFile],
        credentials: T::Array[Dependabot::Credential],
        pull_request_number: Integer,
        author_details: T.nilable(T::Hash[Symbol, String]),
        signature_key: T.nilable(String),
        provider_metadata: T::Hash[Symbol, T.untyped]
      )
        .void
    end
    def initialize(source:, base_commit:, old_commit:, files:,
                   credentials:, pull_request_number:,
                   author_details: nil, signature_key: nil,
                   provider_metadata: {})
      @source              = source
      @base_commit         = base_commit
      @old_commit          = old_commit
      @files               = files
      @credentials         = credentials
      @pull_request_number = pull_request_number
      @author_details      = author_details
      @signature_key       = signature_key
      @provider_metadata   = provider_metadata
    end

    # TODO: Each implementation returns a client-specific type.
    #       We should standardise this to return a `Dependabot::Branch` type instead.
    sig { returns(T.untyped) }
    def update
      case source.provider
      when "github" then github_updater.update
      when "gitlab" then gitlab_updater.update
      when "azure" then azure_updater.update
      else raise "Unsupported provider #{source.provider}"
      end
    end

    private

    sig { returns(Dependabot::PullRequestUpdater::Github) }
    def github_updater
      Github.new(
        source: source,
        base_commit: base_commit,
        old_commit: old_commit,
        files: files,
        credentials: credentials,
        pull_request_number: pull_request_number,
        author_details: author_details,
        signature_key: signature_key
      )
    end

    sig { returns(Dependabot::PullRequestUpdater::Gitlab) }
    def gitlab_updater
      Gitlab.new(
        source: source,
        base_commit: base_commit,
        old_commit: old_commit,
        files: files,
        credentials: credentials,
        pull_request_number: pull_request_number,
        target_project_id: T.cast(provider_metadata[:target_project_id], T.nilable(Integer))
      )
    end

    sig { returns(Dependabot::PullRequestUpdater::Azure) }
    def azure_updater
      Azure.new(
        source: source,
        base_commit: base_commit,
        old_commit: old_commit,
        files: files,
        credentials: credentials,
        pull_request_number: pull_request_number,
        author_details: author_details
      )
    end
  end
end
