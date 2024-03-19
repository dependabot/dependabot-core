# typed: strict
# frozen_string_literal: true

require "aws-sdk-codecommit"
require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module Clients
    class CodeCommit
      extend T::Sig

      class NotFound < StandardError; end

      #######################
      # Constructor methods #
      #######################

      sig do
        params(
          source: Dependabot::Source,
          credentials: T::Array[Dependabot::Credential]
        )
          .returns(Dependabot::Clients::CodeCommit)
      end
      def self.for_source(source:, credentials:)
        credential =
          credentials
          .select { |cred| cred["type"] == "git_source" }
          .find { |cred| cred["region"] == source.hostname }

        new(source, credential)
      end

      ##########
      # Client #
      ##########

      sig do
        params(
          source: Dependabot::Source,
          credentials: T.nilable(Dependabot::Credential)
        )
          .void
      end
      def initialize(source, credentials)
        @source = source
        @cc_client =
          T.let(
            if credentials
              Aws::CodeCommit::Client.new(
                access_key_id: credentials.fetch("username"),
                secret_access_key: credentials.fetch("password"),
                region: credentials.fetch("region")
              )
            else
              Aws::CodeCommit::Client.new
            end,
            Aws::CodeCommit::Client
          )
      end

      # TODO: Should repo be required?
      sig { params(repo: T.nilable(String), branch: String).returns(String) }
      def fetch_commit(repo, branch)
        cc_client.get_branch(
          branch_name: branch,
          repository_name: repo
        ).branch.commit_id
      end

      sig { params(repo: String).returns(String) }
      def fetch_default_branch(repo)
        cc_client.get_repository(
          repository_name: repo
        ).repository_metadata.default_branch
      end

      sig do
        params(
          repo: String, commit: T.nilable(String),
          path: T.nilable(String)
        )
          .returns(Seahorse::Client::Response)
          # .returns(Aws::CodeCommit::Types::GetFolderOutput)
      end
      def fetch_repo_contents(repo, commit = nil, path = nil)
        actual_path = path
        actual_path = "/" if path.to_s.empty?

        cc_client.get_folder(
          repository_name: repo,
          commit_specifier: commit,
          folder_path: actual_path
        )
      end

      sig do
        params(
          repo: String,
          commit: String,
          path: String
        )
          .returns(String)
      end
      def fetch_file_contents(repo, commit, path)
        cc_client.get_file(
          repository_name: repo,
          commit_specifier: commit,
          file_path: path
        ).file_content
        rescue Aws::CodeCommit::Errors::FileDoesNotExistException
          raise NotFound
      end

      sig do
        params(
          branch_name: String
        )
          .returns(String)
      end
      def branch(branch_name)
        cc_client.get_branch(
          repository_name: source.unscoped_repo,
          branch_name: branch_name
        )
      end

      # work around b/c codecommit doesn't have a 'get all commits' api..
      sig do
        params(
          repo: String,
          branch_name: String,
          result_count: Integer
        )
          .returns(T::Array[String])
      end
      def fetch_commits(repo, branch_name, result_count)
        top_commit = fetch_commit(repo, branch_name)
        retrieved_commits = []
        pending_commits = []

        # get the parent commit ids from the latest commit on the default branch
        latest_commit = @cc_client.get_commit(
          repository_name: repo,
          commit_id: top_commit
        )

        # add the parent commit ids to the pending_commits array
        pending_commits.push(*latest_commit.commit.parents)

        # iterate over the array of pending commits and
        # get each of the corresponding parent commits
        until pending_commits.empty? || retrieved_commits.count > result_count
          commit_id = pending_commits[0]

          # get any parent commits from the provided commit
          parent_commits = @cc_client.get_commit(
            repository_name: repo,
            commit_id: commit_id
          )

          # remove the previously retrieved_commits
          # form the pending_commits array
          pending_commits.delete(commit_id)
          # add the commit id to the retrieved_commits array
          retrieved_commits << commit_id
          # add the retrieved parent commits to the pending_commits array
          pending_commits.push(*parent_commits.commit.parents)
        end

        retrieved_commits << top_commit
        result = retrieved_commits | pending_commits
        result
      end

      sig do
        params(
          repo: String,
          branch_name: String
        )
          .returns(Aws::CodeCommit::Types::Commit)
      end
      def commits(repo, branch_name = T.must(source.branch))
        retrieved_commits = fetch_commits(repo, branch_name, 5)

        result = @cc_client.batch_get_commits(
          commit_ids: retrieved_commits,
          repository_name: repo
        )

        # sort the results by date
        result.commits.sort! { |a, b| b.author.date <=> a.author.date }
        result
      end

      sig do
        params(
          repo: String,
          state: String,
          branch: String
        )
          .returns(T::Array[Aws::CodeCommit::Types::PullRequest])
      end
      def pull_requests(repo, state, branch)
        pull_request_ids = @cc_client.list_pull_requests(
          repository_name: repo,
          pull_request_status: state
        ).pull_request_ids

        result = []
        # list_pull_requests only gets us the pull request id
        # get_pull_request has all the info we need
        pull_request_ids.each do |id|
          pr_hash = @cc_client.get_pull_request(
            pull_request_id: id
          )
          # only include PRs from the referenced branch
          if pr_hash.pull_request.pull_request_targets[0]
                    .source_reference.include? branch
            result << pr_hash
          end
        end
        result
      end

      sig do
        params(
          repo: String,
          branch_name: String,
          commit_id: String
        )
          .returns(Aws::CodeCommit::Types::BranchInfo)
      end
      def create_branch(repo, branch_name, commit_id)
        cc_client.create_branch(
          repository_name: repo,
          branch_name: branch_name,
          commit_id: commit_id
        )
      end

      sig do
        params(
          branch_name: String,
          author_name: String,
          base_commit: String,
          commit_message: String,
          files: T::Array[Dependabot::DependencyFile]
        )
          .returns(Aws::CodeCommit::Types::CreateCommitOutput)
      end
      def create_commit(branch_name, author_name, base_commit, commit_message,
                        files)
        cc_client.create_commit(
          repository_name: source.unscoped_repo,
          branch_name: branch_name,
          parent_commit_id: base_commit,
          author_name: author_name,
          commit_message: commit_message,
          put_files: files.map do |file|
            {
              file_path: file.path,
              file_mode: "NORMAL",
              file_content: file.content
            }
          end
        )
      end

      sig do
        params(
          pr_name: String,
          target_branch: String,
          source_branch: String,
          pr_description: String
        )
          .returns(T.nilable(Aws::CodeCommit::Types::CreatePullRequestOutput))
      end
      def create_pull_request(pr_name, target_branch, source_branch,
                              pr_description)
        cc_client.create_pull_request(
          title: pr_name,
          description: pr_description,
          targets: [
            repository_name: source.unscoped_repo,
            source_reference: target_branch,
            destination_reference: source_branch
          ]
        )
      end

      private

      sig { returns(Dependabot::Source) }
      attr_reader :source

      sig { returns(Aws::CodeCommit::Client) }
      attr_reader :cc_client
    end
  end
end
