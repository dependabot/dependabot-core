# frozen_string_literal: true

require "dependabot/clients/gitlab_with_retries"
require "dependabot/pull_request_creator"
require "gitlab"

module Dependabot
  class PullRequestCreator
    class Gitlab
      attr_reader :source, :branch_name, :base_commit, :credentials,
                  :files, :pr_description, :pr_name, :commit_message,
                  :author_details, :labeler, :approvers, :assignees,
                  :milestone, :target_project_id

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

      def gitlab_client_for_source
        @gitlab_client_for_source ||=
          Dependabot::Clients::GitlabWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def branch_exists?
        @branch_ref ||=
          gitlab_client_for_source.branch(source.repo, branch_name)
        true
      rescue ::Gitlab::Error::NotFound
        false
      end

      def commit_exists?
        @commits ||=
          gitlab_client_for_source.commits(source.repo, ref_name: branch_name)
        @commits.first.message == commit_message
      end

      def merge_request_exists?
        gitlab_client_for_source.merge_requests(
          target_project_id || source.repo,
          source_branch: branch_name,
          target_branch: source.branch || default_branch,
          state: "all"
        ).any?
      end

      def create_branch
        gitlab_client_for_source.create_branch(
          source.repo,
          branch_name,
          base_commit
        )
      end

      # @param [DependencyFile] file
      def file_action(file)
        if file.operation == Dependabot::DependencyFile::Operation::DELETE
          "delete"
        elsif file.operation == Dependabot::DependencyFile::Operation::CREATE
          "create"
        else
          "update"
        end
      end

      def create_commit
        return create_submodule_update_commit if files.count == 1 && files.first.type == "submodule"

        actions = files.map do |file|
          {
            action: file_action(file),
            file_path: file.type == "symlink" ? file.symlink_target : file.path,
            content: file.content
          }
        end

        files.select(&:execute_filemode?).each do |file|
          actions << {
            action: "chmod",
            file_path: file.path,
            execute_filemode: true
          }
        end

        gitlab_client_for_source.create_commit(
          source.repo,
          branch_name,
          commit_message,
          actions
        )
      end

      def create_submodule_update_commit
        file = files.first

        gitlab_client_for_source.edit_submodule(
          source.repo,
          file.path.gsub(%r{^/}, ""),
          branch: branch_name,
          commit_sha: file.content,
          commit_message: commit_message
        )
      end

      def create_merge_request
        gitlab_client_for_source.create_merge_request(
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

      def annotate_merge_request(merge_request)
        add_approvers_to_merge_request(merge_request)
      end

      def add_approvers_to_merge_request(merge_request)
        return unless approvers_hash[:approvers] || approvers_hash[:group_approvers]

        gitlab_client_for_source.create_merge_request_level_rule(
          target_project_id || source.repo,
          merge_request.iid,
          name: "dependency-updates",
          approvals_required: 1,
          user_ids: approvers_hash[:approvers],
          group_ids: approvers_hash[:group_approvers]
        )
      end

      def approvers_hash
        @approvers_hash ||= approvers&.transform_keys(&:to_sym) || {}
      end

      def default_branch
        @default_branch ||=
          gitlab_client_for_source.project(source.repo).default_branch
      end
    end
  end
end
