# frozen_string_literal: true

require "octokit"
require "securerandom"
require "dependabot/clients/github_with_retries"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_creator/commit_signer"

# rubocop:disable Metrics/ClassLength
module Dependabot
  class PullRequestCreator
    class Github
      attr_reader :source, :branch_name, :base_commit, :credentials,
                  :files, :pr_description, :pr_name, :commit_message,
                  :author_details, :signature_key, :custom_headers,
                  :labeler, :reviewers, :assignees, :milestone

      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     author_details:, signature_key:, custom_headers:,
                     labeler:, reviewers:, assignees:, milestone:)
        @source         = source
        @branch_name    = branch_name
        @base_commit    = base_commit
        @credentials    = credentials
        @files          = files
        @commit_message = commit_message
        @pr_description = pr_description
        @pr_name        = pr_name
        @author_details = author_details
        @signature_key  = signature_key
        @custom_headers = custom_headers
        @labeler        = labeler
        @reviewers      = reviewers
        @assignees      = assignees
        @milestone      = milestone
      end

      def create
        return if branch_exists?(branch_name) && pull_request_exists?

        commit = create_commit
        branch = create_or_update_branch(commit)
        return unless branch

        pull_request = create_pull_request
        return unless pull_request

        annotate_pull_request(pull_request)

        pull_request
      rescue Octokit::Error => e
        handle_error(e)
      end

      private

      def github_client_for_source
        @github_client_for_source ||=
          Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def branch_exists?(name)
        git_metadata_fetcher.ref_names.include?(name)
      rescue Dependabot::GitDependenciesNotReachable => e
        raise e.cause if e.cause&.message&.include?("is disabled")
        raise e.cause if e.cause.is_a?(Octokit::Unauthorized)
        raise(RepoNotFound, source.url) unless repo_exists?

        retrying ||= false
        raise "Unexpected git error!" if retrying

        retrying = true
        retry
      end

      # Existing pull requests with this branch name that are open or closed.
      # Note: we ignore *merged* pull requests for the branch name as we want
      # to recreate them if the dependency version has regressed.
      def pull_request_exists?
        pull_requests =
          begin
            github_client_for_source.pull_requests(
              source.repo,
              head: "#{source.repo.split('/').first}:#{branch_name}",
              state: "all"
            )
          rescue Octokit::InternalServerError
            # A GitHub bug sometimes means adding `state: all` causes problems.
            # In that case, fall back to making two separate requests.
            open_prs = github_client_for_source.pull_requests(
              source.repo,
              head: "#{source.repo.split('/').first}:#{branch_name}",
              state: "open"
            )

            closed_prs = github_client_for_source.pull_requests(
              source.repo,
              head: "#{source.repo.split('/').first}:#{branch_name}",
              state: "closed"
            )
            [*open_prs, *closed_prs]
          end

        pull_requests.reject(&:merged).any?
      end

      def repo_exists?
        github_client_for_source.repo(source.repo)
        true
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
          raise if retry_count > 10

          sleep(rand(1..1.99))
          retry
        end
      end

      def create_tree
        file_trees = files.map do |file|
          if file.type == "submodule"
            {
              path: file.path.sub(%r{^/}, ""),
              mode: "160000",
              type: "commit",
              sha: file.content
            }
          else
            {
              path: (file.symlink_target || file.path).sub(%r{^/}, ""),
              mode: "100644",
              type: "blob",
              content: file.content
            }
          end
        end

        github_client_for_source.create_tree(
          source.repo,
          file_trees,
          base_tree: base_commit
        )
      end

      def create_or_update_branch(commit)
        if branch_exists?(branch_name)
          update_branch(commit)
        else
          create_branch(commit)
        end
      rescue Octokit::UnprocessableEntity => e
        raise unless e.message.include?("Reference update failed //")

        # A race condition may cause GitHub to fail here, in which case we retry
        retry_count ||= 0
        retry_count += 1
        if retry_count > 10
          raise "Repeatedly failed to create or update branch #{branch_name} "\
                "with commit #{commit.sha}."
        end

        sleep(rand(1..1.99))
        retry
      end

      def create_branch(commit)
        ref = "heads/#{branch_name}"

        begin
          branch =
            github_client_for_source.create_ref(source.repo, ref, commit.sha)
          @branch_name = ref.gsub(%r{^heads/}, "")
          branch
        rescue Octokit::UnprocessableEntity => e
          # Return quietly in the case of a race
          return nil if e.message.match?(/Reference already exists/i)

          retrying_branch_creation ||= false
          raise if retrying_branch_creation

          retrying_branch_creation = true

          # Branch creation will fail if a branch called `dependabot` already
          # exists, since git won't be able to create a dir with the same name
          ref = "heads/#{SecureRandom.hex[0..3] + branch_name}"
          retry
        end
      end

      def update_branch(commit)
        github_client_for_source.update_ref(
          source.repo,
          "heads/#{branch_name}",
          commit.sha,
          true
        )
      end

      def annotate_pull_request(pull_request)
        labeler.label_pull_request(pull_request.number)
        add_reviewers_to_pull_request(pull_request) if reviewers&.any?
        add_assignees_to_pull_request(pull_request) if assignees&.any?
        add_milestone_to_pull_request(pull_request) if milestone
      end

      def add_reviewers_to_pull_request(pull_request)
        reviewers_hash =
          Hash[reviewers.keys.map { |k| [k.to_sym, reviewers[k]] }]

        github_client_for_source.request_pull_request_review(
          source.repo,
          pull_request.number,
          reviewers: reviewers_hash[:reviewers] || [],
          team_reviewers: reviewers_hash[:team_reviewers] || []
        )
      rescue Octokit::UnprocessableEntity => e
        return if invalid_reviewer?(e.message)

        raise
      end

      def invalid_reviewer?(message)
        return true if message.include?("Could not resolve to a node")
        return true if message.include?("not a collaborator")
        return true if message.include?("Could not add requested reviewers")

        false
      end

      def add_assignees_to_pull_request(pull_request)
        github_client_for_source.add_assignees(
          source.repo,
          pull_request.number,
          assignees
        )
      rescue Octokit::NotFound
        # This can happen if a passed assignee login is now an org account
        nil
      end

      def add_milestone_to_pull_request(pull_request)
        github_client_for_source.update_issue(
          source.repo,
          pull_request.number,
          milestone: milestone
        )
      rescue Octokit::UnprocessableEntity => e
        raise unless e.message.include?("code: invalid")
      end

      def create_pull_request
        github_client_for_source.create_pull_request(
          source.repo,
          source.branch || default_branch,
          branch_name,
          pr_name,
          pr_description,
          headers: custom_headers || {}
        )
      rescue Octokit::UnprocessableEntity => e
        handle_pr_creation_error(e)
      end

      def handle_pr_creation_error(error)
        # Ignore races that we lose
        return if error.message.include?("pull request already exists")

        # Ignore cases where the target branch has been deleted
        return if error.message.include?("field: base") &&
                  source.branch &&
                  !branch_exists?(source.branch)

        raise
      end

      def default_branch
        @default_branch ||=
          github_client_for_source.repository(source.repo).default_branch
      end

      def git_metadata_fetcher
        @git_metadata_fetcher ||=
          GitMetadataFetcher.new(
            url: source.url,
            credentials: credentials
          )
      end

      def commit_signature(tree, author_details_with_date)
        CommitSigner.new(
          author_details: author_details_with_date,
          commit_message: commit_message,
          tree_sha: tree.sha,
          parent_sha: base_commit,
          signature_key: signature_key
        ).signature
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      def handle_error(err)
        case err
        when Octokit::Forbidden
          raise RepoDisabled, err.message if err.message.include?("disabled")
          raise RepoArchived, err.message if err.message.include?("archived")

          raise err
        when Octokit::NotFound
          raise err if repo_exists?

          raise RepoNotFound, err.message
        when Octokit::UnprocessableEntity
          raise err unless err.message.include?("no history in common")

          raise NoHistoryInCommon, err.message
        else
          raise err
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity
    end
  end
end
# rubocop:enable Metrics/ClassLength
