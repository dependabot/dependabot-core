# frozen_string_literal: true

require "dependabot/clients/gitlab_with_retries"
require "dependabot/pull_request_creator"
require "gitlab"

module Dependabot
  class PullRequestUpdater
    class Gitlab
      attr_reader :source, :files, :base_commit, :old_commit, :credentials,
                  :pull_request_number, :target_project_id

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

      def update
        return unless merge_request_exists?
        return unless branch_exists?(merge_request.source_branch)

        create_commit
        merge_request.source_branch
      end

      private

      def merge_request_exists?
        merge_request
        true
      rescue ::Gitlab::Error::NotFound
        false
      end

      def merge_request
        @merge_request ||= gitlab_client_for_source.merge_request(
          target_project_id || source.repo,
          pull_request_number
        )
      end

      def gitlab_client_for_source
        @gitlab_client_for_source ||=
          Dependabot::Clients::GitlabWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def branch_exists?(name)
        gitlab_client_for_source.branch(source.repo, name)
      rescue ::Gitlab::Error::NotFound
        false
      end

      def commit_being_updated
        gitlab_client_for_source.commit(source.repo, old_commit)
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
        actions = files.map do |file|
          {
            action: file_action(file),
            file_path: file.type == "symlink" ? file.symlink_target : file.path,
            content: file.content
          }
        end

        gitlab_client_for_source.create_commit(
          source.repo,
          merge_request.source_branch,
          commit_being_updated.title,
          actions,
          force: true,
          start_branch: merge_request.target_branch
        )
      end
    end
  end
end
