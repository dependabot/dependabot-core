# frozen_string_literal: true

require "octokit"
require "securerandom"
require "dependabot/clients/github_with_retries"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_creator/commit_signer"
module Dependabot
  class PullRequestCreator
    # rubocop:disable Metrics/ClassLength
    class Github
      MAX_PR_DESCRIPTION_LENGTH = 65_536 # characters (see #create_pull_request)

      attr_reader :source, :branch_name, :base_commit, :credentials,
                  :files, :pr_description, :pr_name, :commit_message,
                  :author_details, :signature_key, :custom_headers,
                  :labeler, :reviewers, :assignees, :milestone

      def initialize(source:, branch_name:, base_commit:, credentials:,
                     files:, commit_message:, pr_description:, pr_name:,
                     author_details:, signature_key:, custom_headers:,
                     labeler:, reviewers:, assignees:, milestone:,
                     require_up_to_date_base:)
        @source                  = source
        @branch_name             = branch_name
        @base_commit             = base_commit
        @credentials             = credentials
        @files                   = files
        @commit_message          = commit_message
        @pr_description          = pr_description
        @pr_name                 = pr_name
        @author_details          = author_details
        @signature_key           = signature_key
        @custom_headers          = custom_headers
        @labeler                 = labeler
        @reviewers               = reviewers
        @assignees               = assignees
        @milestone               = milestone
        @require_up_to_date_base = require_up_to_date_base
      end

      def create
        return if branch_exists?(branch_name) && unmerged_pull_request_exists?
        return if require_up_to_date_base? && !base_commit_is_up_to_date?

        create_annotated_pull_request
      rescue AnnotationError, Octokit::Error => e
        handle_error(e)
      end

      private

      def require_up_to_date_base?
        @require_up_to_date_base
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def branch_exists?(name)
        git_metadata_fetcher.ref_names.include?(name)
      rescue Dependabot::GitDependenciesNotReachable => e
        raise e.cause if e.cause&.message&.include?("is disabled")
        raise e.cause if e.cause.is_a?(Octokit::Unauthorized)
        raise(RepoNotFound, source.url) unless repo_exists?

        retrying ||= false

        msg = "Unexpected git error!\n\n#{e.cause&.class}: #{e.cause&.message}"
        raise msg if retrying

        retrying = true
        retry
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def unmerged_pull_request_exists?
        pull_requests_for_branch.reject(&:merged).any?
      end

      def pull_requests_for_branch
        @pull_requests_for_branch ||=
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
      end

      def base_commit_is_up_to_date?
        git_metadata_fetcher.head_commit_for_ref(target_branch) == base_commit
      end

      def create_annotated_pull_request
        commit = create_commit
        branch = create_or_update_branch(commit)
        return unless branch

        pull_request = create_pull_request
        return unless pull_request

        begin
          annotate_pull_request(pull_request)
        rescue StandardError => e
          raise AnnotationError.new(e, pull_request)
        end

        pull_request
      end

      def repo_exists?
        github_client_for_source.repo(source.repo)
        true
      rescue Octokit::NotFound
        false
      end

      def create_commit
        tree = create_tree

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
          raise_or_increment_retry_counter(counter: @commit_creation, limit: 3)
          sleep(rand(1..1.99))
          retry
        end
      rescue Octokit::UnprocessableEntity => e
        raise unless e.message == "Tree SHA does not exist"

        raise_or_increment_retry_counter(counter: @tree_creation, limit: 1)
        sleep(rand(1..1.99))
        retry
      end

      def commit_options(tree)
        options = author_details&.any? ? { author: author_details } : {}

        if options[:author]&.any? && signature_key
          options[:author][:date] = Time.now.utc.iso8601
          options[:signature] = commit_signature(tree, options[:author])
        end

        options
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
            content = if file.operation == Dependabot::DependencyFile::Operation::DELETE
                        { sha: nil }
                      elsif file.binary?
                        sha = github_client_for_source.create_blob(
                          source.repo, file.content, "base64"
                        )
                        { sha: sha }
                      else
                        { content: file.content }
                      end

            {
              path: (file.symlink_target ||
                     file.path).sub(%r{^/}, ""),
              mode: (file.mode || "100644"),
              type: "blob"
            }.merge(content)
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
          raise "Repeatedly failed to create or update branch #{branch_name} " \
                "with commit #{commit.sha}."
        end

        sleep(rand(1..1.99))
        retry
      end

      def create_branch(commit)
        ref = "refs/heads/#{branch_name}"

        begin
          branch =
            github_client_for_source.create_ref(source.repo, ref, commit.sha)
          @branch_name = ref.gsub(%r{^refs/heads/}, "")
          branch
        rescue Octokit::UnprocessableEntity => e
          # Return quietly in the case of a race
          return nil if e.message.match?(/Reference already exists/i)

          retrying_branch_creation ||= false
          raise if retrying_branch_creation

          retrying_branch_creation = true

          # Branch creation will fail if a branch called `dependabot` already
          # exists, since git won't be able to create a dir with the same name
          ref = "refs/heads/#{SecureRandom.hex[0..3] + branch_name}"
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
          reviewers.keys.to_h { |k| [k.to_sym, reviewers[k]] }

        github_client_for_source.request_pull_request_review(
          source.repo,
          pull_request.number,
          reviewers: reviewers_hash[:reviewers] || [],
          team_reviewers: reviewers_hash[:team_reviewers] || []
        )
      rescue Octokit::UnprocessableEntity => e
        # Special case GitHub bug for team reviewers
        return if e.message.include?("Could not resolve to a node")

        if invalid_reviewer?(e.message)
          comment_with_invalid_reviewer(pull_request, e.message)
          return
        end

        raise
      end

      def invalid_reviewer?(message)
        return true if message.include?("Could not resolve to a node")
        return true if message.include?("not a collaborator")
        return true if message.include?("Could not add requested reviewers")

        false
      end

      def comment_with_invalid_reviewer(pull_request, message)
        reviewers_hash =
          reviewers.keys.to_h { |k| [k.to_sym, reviewers[k]] }
        reviewers = []
        reviewers += reviewers_hash[:reviewers] || []
        reviewers += (reviewers_hash[:team_reviewers] || []).
                     map { |rv| "#{source.repo.split('/').first}/#{rv}" }

        reviewers_string =
          if reviewers.count == 1
            "`@#{reviewers.first}`"
          else
            names = reviewers.map { |rv| "`@#{rv}`" }
            "#{names[0..-2].join(', ')} and #{names[-1]}"
          end

        msg = "Dependabot tried to add #{reviewers_string} as "
        msg += reviewers.count > 1 ? "reviewers" : "a reviewer"
        msg += " to this PR, but received the following error from GitHub:\n\n" \
               "```\n" \
               "#{message}\n" \
               "```"

        github_client_for_source.add_comment(
          source.repo,
          pull_request.number,
          msg
        )
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
        # Limit PR description to MAX_PR_DESCRIPTION_LENGTH (65,536) characters
        # and truncate with message if over. The API limit is 262,144 bytes
        # (https://github.community/t/maximum-length-for-the-comment-body-in-issues-and-pr/148867/2).
        # As Ruby strings are UTF-8 encoded, this is a pessimistic limit: it
        # presumes the case where all characters are 4 bytes.
        pr_description = @pr_description.dup
        if pr_description && pr_description.length > MAX_PR_DESCRIPTION_LENGTH
          truncated_msg = "...\n\n_Description has been truncated_"
          truncate_length = MAX_PR_DESCRIPTION_LENGTH - truncated_msg.length
          pr_description = (pr_description[0, truncate_length] + truncated_msg)
        end

        github_client_for_source.create_pull_request(
          source.repo,
          target_branch,
          branch_name,
          pr_name,
          pr_description,
          headers: custom_headers || {}
        )
      rescue Octokit::UnprocessableEntity => e
        return handle_pr_creation_error(e) if e.message.include? "Error summary"

        # Sometimes PR creation fails with no details (presumably because the
        # details are internal). It doesn't hurt to retry in these cases, in
        # case the cause is a race.
        retrying_pr_creation ||= false
        raise if retrying_pr_creation

        retrying_pr_creation = true
        retry
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

      def target_branch
        source.branch || default_branch
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

      def raise_or_increment_retry_counter(counter:, limit:)
        counter ||= 0
        counter += 1
        raise if counter > limit
      end

      def github_client_for_source
        @github_client_for_source ||=
          Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def handle_error(err)
        cause = case err
                when AnnotationError
                  err.cause
                else
                  err
                end

        case cause
        when Octokit::Forbidden
          if err.message.include?("disabled")
            raise_custom_error err, RepoDisabled, err.message
          elsif err.message.include?("archived")
            raise_custom_error err, RepoArchived, err.message
          end

          raise err
        when Octokit::NotFound
          raise err if repo_exists?

          raise_custom_error err, RepoNotFound, err.message
        when Octokit::UnprocessableEntity
          raise_custom_error err, NoHistoryInCommon, err.message if err.message.include?("no history in common")

          raise err
        else
          raise err
        end
      end

      def raise_custom_error(base_err, type, message)
        case base_err
        when AnnotationError
          raise AnnotationError.new(
            type.new(message),
            base_err.pull_request
          )
        else
          raise type, message
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
