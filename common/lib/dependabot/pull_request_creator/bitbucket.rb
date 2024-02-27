# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/clients/bitbucket"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class Bitbucket
      extend T::Sig

      sig { returns(Dependabot::Source) }
      attr_reader :source

      sig { returns(String) }
      attr_reader :branch_name

      sig { returns(String) }
      attr_reader :base_commit

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :files

      sig { returns(String) }
      attr_reader :commit_message

      sig { returns(String) }
      attr_reader :pr_description

      sig { returns(String) }
      attr_reader :pr_name

      sig { returns(T.nilable(T::Hash[Symbol, String])) }
      attr_reader :author_details

      sig { returns(T.nilable(Dependabot::PullRequestCreator::Labeler)) }
      attr_reader :labeler

      sig { returns(T.nilable(Integer)) }
      attr_reader :work_item

      # BitBucket Cloud accepts > 1MB characters, but they display poorly in the UI, so limiting to 4x 65,536
      PR_DESCRIPTION_MAX_LENGTH = 262_143 # 0 based count

      sig do
        params(
          source: Dependabot::Source,
          branch_name: String,
          base_commit: String,
          credentials: T::Array[Dependabot::Credential],
          files: T::Array[Dependabot::DependencyFile],
          commit_message: String,
          pr_description: String,
          pr_name: String,
          author_details: T.nilable(T::Hash[Symbol, String]),
          labeler: T.nilable(Dependabot::PullRequestCreator::Labeler),
          work_item: T.nilable(Integer)
        )
          .void
      end
      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     author_details:, labeler: nil, work_item: nil)
        @source         = source
        @branch_name    = branch_name
        @base_commit    = base_commit
        @credentials    = credentials
        @files          = files
        @commit_message = commit_message
        @pr_description = pr_description
        @pr_name        = pr_name
        @author_details = author_details
        @labeler        = labeler
        @work_item      = work_item
      end

      sig { void }
      def create
        return if branch_exists? && pull_request_exists?

        # FIXME: Copied from Azure, but not verified whether this is true
        # For Bitbucket we create or update a branch in the same request as creating
        # a commit (so we don't need create or update branch logic here)
        create_commit

        create_pull_request
      end

      private

      sig { returns(Dependabot::Clients::Bitbucket) }
      def bitbucket_client_for_source
        @bitbucket_client_for_source ||=
          T.let(
            Dependabot::Clients::Bitbucket.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::Bitbucket)
          )
      end

      sig { returns(T::Boolean) }
      def branch_exists?
        !bitbucket_client_for_source.branch(source.repo, branch_name).nil?
      rescue Clients::Bitbucket::NotFound
        false
      end

      sig { returns(T::Boolean) }
      def pull_request_exists?
        bitbucket_client_for_source.pull_requests(
          source.repo,
          branch_name,
          source.branch || default_branch
        ).any?
      end

      sig { void }
      def create_commit
        author = author_details&.slice(:name, :email)
        author = nil unless author&.any?

        bitbucket_client_for_source.create_commit(
          source.repo,
          branch_name,
          base_commit,
          commit_message,
          files,
          author
        )
      end

      sig { void }
      def create_pull_request
        bitbucket_client_for_source.create_pull_request(
          source.repo,
          pr_name,
          branch_name,
          source.branch || default_branch,
          pr_description,
          nil,
          work_item
        )
      end

      sig { returns(String) }
      def default_branch
        @default_branch ||=
          T.let(
            bitbucket_client_for_source.fetch_default_branch(source.repo),
            T.nilable(String)
          )
      end
    end
  end
end
