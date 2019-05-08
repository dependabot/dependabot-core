# frozen_string_literal: true

require "octokit"
require "dependabot/clients/github_with_retries"
require "dependabot/pull_request_creator/commit_signer"
require "dependabot/pull_request_updater"

module Dependabot
  class PullRequestUpdater
    class Github
      attr_reader :source, :files, :base_commit, :old_commit, :credentials,
                  :pull_request_number, :author_details, :signature_key

      def initialize(source:, base_commit:, old_commit:, files:,
                     credentials:, pull_request_number:,
                     author_details: nil, signature_key: nil)
        @source              = source
        @base_commit         = base_commit
        @old_commit          = old_commit
        @files               = files
        @credentials         = credentials
        @pull_request_number = pull_request_number
        @author_details      = author_details
        @signature_key       = signature_key
      end

      def update
        return unless branch_exists?

        commit = create_commit
        branch = update_branch(commit)
        update_pull_request_target_branch
        branch
      end

      private

      def update_pull_request_target_branch
        target_branch = source.branch || pull_request.base.repo.default_branch
        return if target_branch == pull_request.base.ref

        github_client_for_source.update_pull_request(
          source.repo,
          pull_request_number,
          base: target_branch
        )
      rescue Octokit::UnprocessableEntity => e
        # Return quietly if the PR has been closed
        return nil if e.message.match?(/closed pull request/i)

        raise
      end

      def github_client_for_source
        @github_client_for_source ||=
          Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def pull_request
        @pull_request ||=
          github_client_for_source.pull_request(
            source.repo,
            pull_request_number
          )
      end

      def branch_exists?
        github_client_for_source.branch(source.repo, pull_request.head.ref)
      rescue Octokit::NotFound
        false
      end

      def create_commit
        tree = create_tree

        options = author_details&.any? ? { author: author_details } : {}

        if options[:author]&.any? && signature_key
          options[:author][:date] = Time.now.utc.iso8601
          options[:signature] = commit_signature(tree, options[:author])
        end

        begin
          github_client_for_source.create_commit(
            source.repo,
            commit_message,
            tree.sha,
            base_commit,
            options
          )
        rescue Octokit::UnprocessableEntity => e
          raise unless e.message == "Tree SHA does not exist"

          # Sometimes a race condition on GitHub's side means we get an error
          # here. No harm in retrying if we do.
          retry_count ||= 0
          retry_count += 1
          raise if retry_count > 3

          sleep(rand(1..1.99))
          retry
        end
      end

      def create_tree
        file_trees = files.map do |file|
          if file.type == "file"
            {
              path: file.path.sub(%r{^/}, ""),
              mode: "100644",
              type: "blob",
              content: file.content
            }
          elsif file.type == "submodule"
            {
              path: file.path.sub(%r{^/}, ""),
              mode: "160000",
              type: "commit",
              sha: file.content
            }
          else
            raise "Unknown file type #{file.type}"
          end
        end

        github_client_for_source.create_tree(
          source.repo,
          file_trees,
          base_tree: base_commit
        )
      end

      def update_branch(commit)
        github_client_for_source.update_ref(
          source.repo,
          "heads/" + pull_request.head.ref,
          commit.sha,
          true
        )
      rescue Octokit::UnprocessableEntity => e
        # Return quietly if the branch has been deleted
        return nil if e.message.match?(/Reference does not exist/i)

        # Return quietly if the branch has been merged
        return nil if e.message.match?(/Reference cannot be updated/i)

        raise
      end

      def commit_message
        @commit_message ||=
          if pull_request.commits == 1
            github_client_for_source.
              git_commit(source.repo, pull_request.head.sha).
              message
          else
            author_name = author_details&.fetch(:name, nil) || "dependabot[bot]"
            commits =
              github_client_for_source.
              pull_request_commits(source.repo, pull_request_number)

            commit =
              commits.find { |c| c.sha == old_commit } ||
              commits.find { |c| c.commit.author.name == author_name } ||
              commits.first

            commit.commit.message
          end
      end

      def commit_signature(tree, author_details_with_date)
        PullRequestCreator::CommitSigner.new(
          author_details: author_details_with_date,
          commit_message: commit_message,
          tree_sha: tree.sha,
          parent_sha: base_commit,
          signature_key: signature_key
        ).signature
      end
    end
  end
end
