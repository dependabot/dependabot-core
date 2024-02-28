# typed: strict
# frozen_string_literal: true

require "gitlab"
require "sorbet-runtime"

require "dependabot/clients/gitlab_with_retries"
require "dependabot/credential"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestUpdater
    class Gitlab
      extend T::Sig

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

      sig { returns(T.nilable(Integer)) }
      attr_reader :target_project_id

      sig do
        params(
          source: Dependabot::Source,
          base_commit: String,
          old_commit: String,
          files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          pull_request_number: Integer,
          target_project_id: T.nilable(Integer)
        )
          .void
      end
      def initialize(source:, base_commit:, old_commit:, files:,
                     credentials:, pull_request_number:, target_project_id:)
        @source              = source
        @base_commit         = base_commit
        @old_commit          = old_commit
        @files               = files
        @credentials         = credentials
        @pull_request_number = pull_request_number
        @target_project_id   = target_project_id
      end

      sig { returns(T.nilable(String)) }
      def update
        return unless merge_request_exists?
        return unless branch_exists?(merge_request.source_branch)

        create_commit
        merge_request.source_branch
      end

      private

      sig { returns(T::Boolean) }
      def merge_request_exists?
        merge_request
        true
      rescue ::Gitlab::Error::NotFound
        false
      end

      sig { returns(T.untyped) }
      def merge_request
        @merge_request ||= T.let(
          T.unsafe(gitlab_client_for_source).merge_request(
            target_project_id || source.repo,
            pull_request_number
          ),
          T.untyped
        )
      end

      sig { returns(Dependabot::Clients::GitlabWithRetries) }
      def gitlab_client_for_source
        @gitlab_client_for_source ||=
          T.let(
            Dependabot::Clients::GitlabWithRetries.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::GitlabWithRetries)
          )
      end

      sig { params(name: String).returns(T::Boolean) }
      def branch_exists?(name)
        !T.unsafe(gitlab_client_for_source).branch(source.repo, name).nil?
      rescue ::Gitlab::Error::NotFound
        false
      end

      # TODO: This needs to be typed when the underlying client is
      sig { returns(T.untyped) }
      def commit_being_updated
        T.unsafe(gitlab_client_for_source).commit(source.repo, old_commit)
      end

      sig { void }
      def create_commit
        gitlab_client_for_source.create_commit(
          source.repo,
          merge_request.source_branch,
          commit_being_updated.title,
          files,
          force: true,
          start_branch: merge_request.target_branch
        )
      end
    end
  end
end
