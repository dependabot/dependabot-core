# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/credential"
require "dependabot/clients/azure"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class Azure
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

      sig { returns(Dependabot::PullRequestCreator::Labeler) }
      attr_reader :labeler

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :reviewers

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :assignees

      sig { returns(T.nilable(Integer)) }
      attr_reader :work_item

      # Azure DevOps limits PR descriptions to a max of 4,000 characters in UTF-16 encoding:
      # https://developercommunity.visualstudio.com/content/problem/608770/remove-4000-character-limit-on-pull-request-descri.html
      PR_DESCRIPTION_MAX_LENGTH = 3_999 # 0 based count
      PR_DESCRIPTION_ENCODING = Encoding::UTF_16

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
          labeler: Dependabot::PullRequestCreator::Labeler,
          reviewers: T.nilable(T::Array[String]),
          assignees: T.nilable(T::Array[String]),
          work_item: T.nilable(Integer)
        )
          .void
      end
      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     author_details:, labeler:, reviewers: nil, assignees: nil, work_item: nil)
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
        @reviewers      = reviewers
        @assignees      = assignees
        @work_item      = work_item
      end

      sig { returns(T.nilable(Excon::Response)) }
      def create
        return if branch_exists? && pull_request_exists?

        # For Azure we create or update a branch in the same request as creating
        # a commit (so we don't need create or update branch logic here)
        create_commit

        create_pull_request
      end

      private

      sig { returns(Dependabot::Clients::Azure) }
      def azure_client_for_source
        @azure_client_for_source ||=
          T.let(
            Dependabot::Clients::Azure.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::Azure)
          )
      end

      sig { returns(T::Boolean) }
      def branch_exists?
        !azure_client_for_source.branch(branch_name).nil?
      rescue ::Dependabot::Clients::Azure::NotFound
        false
      end

      sig { returns(T::Boolean) }
      def pull_request_exists?
        azure_client_for_source.pull_requests(
          branch_name,
          source.branch || default_branch
        ).any?
      end

      sig { void }
      def create_commit
        author = author_details&.slice(:name, :email, :date)
        author = nil unless author&.any?

        azure_client_for_source.create_commit(
          branch_name,
          base_commit,
          commit_message,
          files,
          author
        )
      end

      sig { returns(Excon::Response) }
      def create_pull_request
        azure_client_for_source.create_pull_request(
          pr_name,
          branch_name,
          source.branch || default_branch,
          pr_description,
          labeler.labels_for_pr,
          reviewers,
          assignees,
          work_item
        )
      end

      sig { returns(String) }
      def default_branch
        @default_branch ||=
          T.let(
            azure_client_for_source.fetch_default_branch(source.repo),
            T.nilable(String)
          )
      end
    end
  end
end
