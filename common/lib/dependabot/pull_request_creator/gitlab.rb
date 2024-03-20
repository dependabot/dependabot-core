# typed: strict
# frozen_string_literal: true

require "gitlab"
require "sorbet-runtime"

require "dependabot/clients/gitlab_with_retries"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class Gitlab
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
      attr_reader :pr_description

      sig { returns(String) }
      attr_reader :pr_name

      sig { returns(String) }
      attr_reader :commit_message

      sig { returns(T.nilable(T::Hash[Symbol, String])) }
      attr_reader :author_details

      sig { returns(Dependabot::PullRequestCreator::Labeler) }
      attr_reader :labeler

      sig { returns(T.nilable(T::Hash[Symbol, T::Array[Integer]])) }
      attr_reader :approvers

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :assignees

      sig { returns(T.nilable(T.any(T::Array[String], Integer))) }
      attr_reader :milestone

      sig { returns(T.nilable(Integer)) }
      attr_reader :target_project_id

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
          approvers: T.nilable(T::Hash[Symbol, T::Array[Integer]]),
          assignees: T.nilable(T::Array[Integer]),
          milestone: T.nilable(T.any(T::Array[String], Integer)),
          target_project_id: T.nilable(Integer)
        )
          .void
      end
      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     author_details:, labeler:, approvers:, assignees:,
                     milestone:, target_project_id:)
        @source            = source
        @branch_name       = branch_name
        @base_commit       = base_commit
        @credentials       = credentials
        @files             = files
        @commit_message    = commit_message
        @pr_description    = pr_description
        @pr_name           = pr_name
        @author_details    = author_details
        @labeler           = labeler
        @approvers         = approvers
        @assignees         = assignees
        @milestone         = milestone
        @target_project_id = target_project_id
      end

      sig { returns(T.nilable(::Gitlab::ObjectifiedHash)) }
      def create
        return if branch_exists? && merge_request_exists?

        if branch_exists?
          create_commit unless commit_exists?
        else
          create_branch
          create_commit
        end

        labeler.create_default_labels_if_required
        merge_request = create_merge_request
        return unless merge_request

        annotate_merge_request(merge_request)

        merge_request
      end

      private

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

      sig { returns(T::Boolean) }
      def branch_exists?
        @branch_ref ||=
          T.let(
            T.unsafe(gitlab_client_for_source).branch(source.repo, branch_name),
            T.nilable(::Gitlab::ObjectifiedHash)
          )
        true
      rescue ::Gitlab::Error::NotFound
        false
      end

      sig { returns(T::Boolean) }
      def commit_exists?
        @commits ||=
          T.let(
            T.unsafe(gitlab_client_for_source).commits(source.repo, ref_name: branch_name),
            T.nilable(::Gitlab::PaginatedResponse)
          )
        @commits.first.message == commit_message
      end

      sig { returns(T::Boolean) }
      def merge_request_exists?
        T.unsafe(gitlab_client_for_source).merge_requests(
          target_project_id || source.repo,
          source_branch: branch_name,
          target_branch: source.branch || default_branch,
          state: "all"
        ).any?
      end

      sig { returns(::Gitlab::ObjectifiedHash) }
      def create_branch
        T.unsafe(gitlab_client_for_source).create_branch(
          source.repo,
          branch_name,
          base_commit
        )
      end

      sig { returns(::Gitlab::ObjectifiedHash) }
      def create_commit
        return create_submodule_update_commit if files.count == 1 && T.must(files.first).type == "submodule"

        gitlab_client_for_source.create_commit(
          source.repo,
          branch_name,
          commit_message,
          files
        )
      end

      sig { returns(::Gitlab::ObjectifiedHash) }
      def create_submodule_update_commit
        file = T.must(files.first)

        T.unsafe(gitlab_client_for_source).edit_submodule(
          source.repo,
          file.path.gsub(%r{^/}, ""),
          branch: branch_name,
          commit_sha: file.content,
          commit_message: commit_message
        )
      end

      sig { returns(T.nilable(::Gitlab::ObjectifiedHash)) }
      def create_merge_request
        T.unsafe(gitlab_client_for_source).create_merge_request(
          source.repo,
          pr_name,
          source_branch: branch_name,
          target_branch: source.branch || default_branch,
          description: pr_description,
          remove_source_branch: true,
          assignee_ids: assignees,
          labels: labeler.labels_for_pr.join(","),
          milestone_id: milestone,
          target_project_id: target_project_id,
          reviewer_ids: approvers_hash[:reviewers]
        )
      end

      sig { params(merge_request: ::Gitlab::ObjectifiedHash).returns(T.nilable(::Gitlab::ObjectifiedHash)) }
      def annotate_merge_request(merge_request)
        add_approvers_to_merge_request(merge_request)
      end

      sig { params(merge_request: ::Gitlab::ObjectifiedHash).returns(T.nilable(::Gitlab::ObjectifiedHash)) }
      def add_approvers_to_merge_request(merge_request)
        return unless approvers_hash[:approvers] || approvers_hash[:group_approvers]

        T.unsafe(gitlab_client_for_source).create_merge_request_level_rule(
          target_project_id || source.repo,
          T.unsafe(merge_request).iid,
          name: "dependency-updates",
          approvals_required: 1,
          user_ids: approvers_hash[:approvers],
          group_ids: approvers_hash[:group_approvers]
        )
      end

      sig { returns(T::Hash[Symbol, T::Array[Integer]]) }
      def approvers_hash
        @approvers_hash ||= T.let(
          approvers || {},
          T.nilable(T::Hash[Symbol, T::Array[Integer]])
        )
      end

      sig { returns(String) }
      def default_branch
        @default_branch ||=
          T.let(
            T.unsafe(gitlab_client_for_source).project(source.repo).default_branch,
            T.nilable(String)
          )
      end
    end
  end
end
