# frozen_string_literal: true

require "octokit"
require "dependabot/clients/github_with_retries"
require "dependabot/pull_request/github"
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
        return unless pull_request_exists?
        return unless branch_exists?(pull_request.head.ref)

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
        handle_pr_update_error(e)
      end

      def handle_pr_update_error(error)
        # Return quietly if the PR has been closed
        return if error.message.match?(/closed pull request/i)

        # Ignore cases where the target branch has been deleted
        return if error.message.include?("field: base") &&
                  source.branch &&
                  !branch_exists?(source.branch)

        raise error
      end

      def github_client_for_source
        @github_client_for_source ||=
          Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def pull_request_exists?
        pull_request
        true
      rescue Octokit::NotFound
        false
      end

      def pull_request
        @pull_request ||=
          github_client_for_source.pull_request(
            source.repo,
            pull_request_number
          )
      end

      def branch_exists?(name)
        github_client_for_source.branch(source.repo, name)
      rescue Octokit::NotFound
        false
      end

      def create_commit
        pull_reguest_client = Dependabot::PullRequest::Github.new(github_client_for_source)
        tree = pull_reguest_client.create_tree(source.repo, base_commit, files)

        begin
          github_client_for_source.create_commit(
            source.repo,
            commit_message,
            tree.sha,
            base_commit,
            commit_options(tree)
          )
        rescue Octokit::UnprocessableEntity => e
          raise unless e.message == "Tree SHA does not exist"

          # Sometimes a race condition on GitHub's side means we get an error
          # here. No harm in retrying if we do.
          retry_count ||= 0
          retry_count += 1
          raise if retry_count > 10

          sleep(rand(1..1.99))
          retry
        end
      end

      def commit_options(tree)
        options = author_details&.any? ? { author: author_details } : {}

        if options[:author]&.any? && signature_key
          options[:author][:date] = Time.now.utc.iso8601
          options[:signature] = commit_signature(tree, options[:author])
        end

        options
      end

      def update_branch(commit)
        github_client_for_source.update_ref(
          source.repo,
          "heads/" + pull_request.head.ref,
          commit.sha,
          true
        )
      rescue Octokit::UnprocessableEntity => e
        # Return quietly if the branch has been deleted or merged
        return nil if e.message.match?(/Reference does not exist/i)
        return nil if e.message.match?(/Reference cannot be updated/i)

        if e.message.match?(/protected branch/i) ||
           e.message.match?(/not authorized to push/i) ||
           e.message.include?("must not contain merge commits") ||
           e.message.match?(/required status check/i)
          raise BranchProtected
        end

        raise
      end

      def commit_message
        fallback_message =
          "#{pull_request.title}" \
          "\n\n" \
          "Dependabot couldn't find the original pull request head commit, " \
          "#{old_commit}."

        # Take the commit message from the old commit. If the old commit can't
        # be found, use the PR title as the commit message.
        commit_being_updated&.message || fallback_message
      end

      def commit_being_updated
        return @commit_being_updated if defined?(@commit_being_updated)

        @commit_being_updated =
          if pull_request.commits == 1
            github_client_for_source.
              git_commit(source.repo, pull_request.head.sha)
          else
            commits =
              github_client_for_source.
              pull_request_commits(source.repo, pull_request_number)

            commit = commits.find { |c| c.sha == old_commit }
            commit&.commit
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
