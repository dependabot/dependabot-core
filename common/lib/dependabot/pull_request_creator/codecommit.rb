# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/clients/codecommit"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class Codecommit
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

      # CodeCommit limits PR descriptions to a max length of 10,240 characters:
      # https://docs.aws.amazon.com/codecommit/latest/APIReference/API_PullRequest.html
      PR_DESCRIPTION_MAX_LENGTH = 10_239 # 0 based count

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
          require_up_to_date_base: T::Boolean
        )
          .void
      end
      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     author_details:, labeler:, require_up_to_date_base:)
        @source                  = source
        @branch_name             = branch_name
        @base_commit             = base_commit
        @credentials             = credentials
        @files                   = files
        @commit_message          = commit_message
        @pr_description          = pr_description
        @pr_name                 = pr_name
        @author_details          = author_details
        @labeler                 = labeler
        @require_up_to_date_base = require_up_to_date_base
      end

      sig { void }
      def create
        return if branch_exists?(branch_name) && unmerged_pull_request_exists?
        return if require_up_to_date_base? && !base_commit_is_up_to_date?

        create_pull_request
      end

      private

      sig { returns(T::Boolean) }
      def require_up_to_date_base?
        @require_up_to_date_base
      end

      sig { returns(T::Boolean) }
      def base_commit_is_up_to_date?
        codecommit_client_for_source.fetch_commit(
          source.repo,
          branch_name
        ) == base_commit
      end

      sig { returns(T.nilable(Aws::CodeCommit::Types::CreatePullRequestOutput)) }
      def create_pull_request
        branch = create_or_get_branch(base_commit)
        return unless branch

        create_commit

        pull_request = codecommit_client_for_source.create_pull_request(
          pr_name,
          branch_name,
          source.branch || default_branch,
          pr_description
          # codecommit doesn't support PR labels
        )
        return unless pull_request

        pull_request
      end

      sig { params(commit: String).returns(T.nilable(String)) }
      def create_or_get_branch(commit)
        # returns the branch name
        if branch_exists?(branch_name)
          branch_name
        else
          create_branch(commit)
        end
      end

      sig { params(commit: String).returns(String) }
      def create_branch(commit)
        # codecommit returns an empty response on create branch success
        codecommit_client_for_source.create_branch(source.repo, branch_name,
                                                   commit)
        @branch_name = branch_name
        branch_name
      end

      sig { returns(Dependabot::Clients::CodeCommit) }
      def codecommit_client_for_source
        @codecommit_client_for_source ||=
          T.let(
            Dependabot::Clients::CodeCommit.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::CodeCommit)
          )
      end

      sig { params(branch_name: String).returns(T::Boolean) }
      def branch_exists?(branch_name)
        @branch_ref ||= T.let(
          codecommit_client_for_source.branch(branch_name),
          T.nilable(String)
        )
        !@branch_ref.nil?
        rescue Aws::CodeCommit::Errors::BranchDoesNotExistException
          false
      end

      sig { returns(T::Boolean) }
      def unmerged_pull_request_exists?
        unmerged_prs = []
        pull_requests_for_branch.each do |pr|
          unless T.unsafe(pr).pull_request
                  .pull_request_targets[0].merge_metadata.is_merged
            unmerged_prs << pr
          end
        end
        unmerged_prs.any?
      end

      sig { returns(T::Array[Aws::CodeCommit::Types::PullRequest]) }
      def pull_requests_for_branch
        @pull_requests_for_branch ||=
          T.let(
            begin
              open_prs = codecommit_client_for_source.pull_requests(
                source.repo,
                "open",
                source.branch || default_branch
              )
              closed_prs = codecommit_client_for_source.pull_requests(
                source.repo,
                "closed",
                source.branch || default_branch
              )

              [*open_prs, *closed_prs]
            end,
            T.nilable(T::Array[Aws::CodeCommit::Types::PullRequest])
          )
      end

      sig { void }
      def create_commit
        author = author_details&.slice(:name, :email, :date)&.values&.first

        codecommit_client_for_source.create_commit(
          branch_name,
          author.to_s,
          base_commit,
          commit_message,
          files
        )
      end

      sig { returns(String) }
      def default_branch
        @default_branch ||=
          T.let(
            codecommit_client_for_source.fetch_default_branch(source.repo),
            T.nilable(String)
          )
      end
    end
  end
end
