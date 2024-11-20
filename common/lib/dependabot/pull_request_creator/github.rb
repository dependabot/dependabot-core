# typed: strict
# frozen_string_literal: true

require "octokit"
require "securerandom"
require "sorbet-runtime"

require "dependabot/clients/github_with_retries"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_creator/commit_signer"

module Dependabot
  class PullRequestCreator
    class Github
      extend T::Sig

      # GitHub limits PR descriptions to a max of 65,536 characters:
      # https://github.com/orgs/community/discussions/27190#discussioncomment-3726017
      PR_DESCRIPTION_MAX_LENGTH = 65_535 # 0 based count

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

      sig { returns(T.nilable(String)) }
      attr_reader :signature_key

      sig { returns(T.nilable(T::Hash[String, String])) }
      attr_reader :custom_headers

      sig { returns(Dependabot::PullRequestCreator::Labeler) }
      attr_reader :labeler

      sig { returns(T.nilable(T::Hash[String, T::Array[String]])) }
      attr_reader :reviewers

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :assignees

      sig { returns(T.nilable(Integer)) }
      attr_reader :milestone

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
          signature_key: T.nilable(String),
          custom_headers: T.nilable(T::Hash[String, String]),
          labeler: Dependabot::PullRequestCreator::Labeler,
          reviewers: T.nilable(T::Hash[String, T::Array[String]]),
          assignees: T.nilable(T::Array[String]),
          milestone: T.nilable(Integer),
          require_up_to_date_base: T::Boolean
        )
          .void
      end
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

      sig { returns(T.untyped) }
      def create
        Dependabot.logger.info(
          "Initiating Github pull request."
        )

        if branch_exists?(branch_name) && no_pull_request_exists?
          Dependabot.logger.info(
            "Existing branch \"#{branch_name}\" found. Pull request not created."
          )
          raise BranchAlreadyExists, "Duplicate branch #{branch_name} already exists"
        end

        if branch_exists?(branch_name) && open_pull_request_exists?
          raise UnmergedPRExists, "PR ##{open_pull_requests.first.number} already exists"
        end
        if require_up_to_date_base? && !base_commit_is_up_to_date?
          raise BaseCommitNotUpToDate, "HEAD #{head_commit} does not match base #{base_commit}"
        end

        create_annotated_pull_request
      rescue AnnotationError, Octokit::Error => e
        handle_error(e)
      end

      private

      sig { returns(T::Boolean) }
      def require_up_to_date_base?
        @require_up_to_date_base
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(name: String).returns(T::Boolean) }
      def branch_exists?(name)
        Dependabot.logger.info(
          "Checking if branch #{name} already exists."
        )

        git_metadata_fetcher.ref_names.include?(name)
      rescue Dependabot::GitDependenciesNotReachable => e
        raise T.must(e.cause) if e.cause&.message&.include?("is disabled")
        raise T.must(e.cause) if e.cause.is_a?(Octokit::Unauthorized)
        raise(RepoNotFound, source.url) unless repo_exists?

        retrying ||= T.let(false, T::Boolean)

        msg = "Unexpected git error!\n\n#{e.cause&.class}: #{e.cause&.message}"
        raise msg if retrying

        retrying = true
        retry
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { returns(T::Boolean) }
      def no_pull_request_exists?
        pull_requests_for_branch.none?
      end

      sig { returns(T::Boolean) }
      def open_pull_request_exists?
        open_pull_requests.any?
      end

      sig { returns(T::Array[T.untyped]) }
      def open_pull_requests
        pull_requests_for_branch.reject(&:closed).reject(&:merged)
      end

      sig { returns(T::Array[T.untyped]) }
      def pull_requests_for_branch
        @pull_requests_for_branch ||=
          T.let(
            begin
              T.unsafe(github_client_for_source).pull_requests(
                source.repo,
                head: "#{source.repo.split('/').first}:#{branch_name}",
                state: "all"
              )
            rescue Octokit::InternalServerError
              # A GitHub bug sometimes means adding `state: all` causes problems.
              # In that case, fall back to making two separate requests.
              open_prs = T.unsafe(github_client_for_source).pull_requests(
                source.repo,
                head: "#{source.repo.split('/').first}:#{branch_name}",
                state: "open"
              )

              closed_prs = T.unsafe(github_client_for_source).pull_requests(
                source.repo,
                head: "#{source.repo.split('/').first}:#{branch_name}",
                state: "closed"
              )
              [*open_prs, *closed_prs]
            end,
            T.nilable(T::Array[T.untyped])
          )
      end

      sig { returns(T::Boolean) }
      def base_commit_is_up_to_date?
        head_commit == base_commit
      end

      sig { returns(T.nilable(String)) }
      def head_commit
        @head_commit ||= T.let(
          git_metadata_fetcher.head_commit_for_ref(target_branch),
          T.nilable(String)
        )
      end

      sig { returns(T.untyped) }
      def create_annotated_pull_request
        commit = create_commit
        branch = create_or_update_branch(commit)
        raise UnexpectedError, "Branch not created" unless branch

        pull_request = create_pull_request
        raise UnexpectedError, "PR not created" unless pull_request

        begin
          annotate_pull_request(pull_request)
        rescue StandardError => e
          raise AnnotationError.new(e, pull_request)
        end

        pull_request
      end

      sig { returns(T::Boolean) }
      def repo_exists?
        T.unsafe(github_client_for_source).repo(source.repo)
        true
      rescue Octokit::NotFound
        false
      end

      sig { returns(T.untyped) }
      def create_commit
        tree = create_tree

        begin
          T.unsafe(github_client_for_source).create_commit(
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
          @commit_creation ||= T.let(0, T.nilable(Integer))
          raise_or_increment_retry_counter(counter: @commit_creation, limit: 3)
          sleep(rand(1..1.99))
          retry
        end
      rescue Octokit::UnprocessableEntity => e
        raise unless e.message == "Tree SHA does not exist"

        @tree_creation ||= T.let(0, T.nilable(Integer))
        raise_or_increment_retry_counter(counter: @tree_creation, limit: 1)
        sleep(rand(1..1.99))
        retry
      end

      sig { params(tree: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def commit_options(tree)
        options = author_details&.any? ? { author: author_details } : {}

        if options[:author]&.any? && signature_key
          options[:author][:date] = Time.now.utc.iso8601
          options[:signature] = commit_signature(tree, options[:author])
        end

        options
      end

      sig { returns(T.untyped) }
      def create_tree
        file_trees = files.map do |file|
          if file.type == "submodule"
            {
              path: file.path.sub(%r{^/}, ""),
              mode: Dependabot::DependencyFile::Mode::SUBMODULE,
              type: "commit",
              sha: file.content
            }
          else
            content = if file.operation == Dependabot::DependencyFile::Operation::DELETE
                        { sha: nil }
                      elsif file.binary?
                        sha = T.unsafe(github_client_for_source).create_blob(
                          source.repo, file.content, "base64"
                        )
                        { sha: sha }
                      else
                        { content: file.content }
                      end

            {
              path: file.realpath,
              mode: file.mode || Dependabot::DependencyFile::Mode::FILE,
              type: "blob"
            }.merge(content)
          end
        end

        T.unsafe(github_client_for_source).create_tree(
          source.repo,
          file_trees,
          base_tree: base_commit
        )
      end

      sig { params(commit: T.untyped).returns(T.untyped) }
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
        raise if retry_count > 10

        sleep(rand(1..1.99))
        retry
      end

      sig { params(commit: T.untyped).returns(T.untyped) }
      def create_branch(commit)
        ref = "refs/heads/#{branch_name}"

        begin
          branch =
            T.unsafe(github_client_for_source).create_ref(source.repo, ref, commit.sha)
          @branch_name = ref.gsub(%r{^refs/heads/}, "")
          branch
        rescue Octokit::UnprocessableEntity => e
          raise if e.message.match?(/Reference already exists/i)

          retrying_branch_creation ||= T.let(false, T::Boolean)
          raise if retrying_branch_creation

          retrying_branch_creation = true

          # Branch creation will fail if a branch called `dependabot` already
          # exists, since git won't be able to create a dir with the same name
          ref = "refs/heads/#{T.must(SecureRandom.hex[0..3]) + branch_name}"
          retry
        end
      end

      sig { params(commit: T.untyped).void }
      def update_branch(commit)
        T.unsafe(github_client_for_source).update_ref(
          source.repo,
          "heads/#{branch_name}",
          commit.sha,
          true
        )
      end

      sig { params(pull_request: T.untyped).void }
      def annotate_pull_request(pull_request)
        labeler.label_pull_request(pull_request.number)
        add_reviewers_to_pull_request(pull_request) if reviewers&.any?
        add_assignees_to_pull_request(pull_request) if assignees&.any?
        add_milestone_to_pull_request(pull_request) if milestone
      end

      sig { params(pull_request: T.untyped).void }
      def add_reviewers_to_pull_request(pull_request)
        reviewers_hash =
          T.must(reviewers).keys.to_h { |k| [k.to_sym, T.must(reviewers)[k]] }

        T.unsafe(github_client_for_source).request_pull_request_review(
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

      sig { params(message: String).returns(T::Boolean) }
      def invalid_reviewer?(message)
        return true if message.include?("Could not resolve to a node")
        return true if message.include?("not a collaborator")
        return true if message.include?("Could not add requested reviewers")
        return true if message.include?("Review cannot be requested from pull request author")

        false
      end

      sig { params(pull_request: T.untyped, message: String).void }
      def comment_with_invalid_reviewer(pull_request, message)
        reviewers_hash =
          T.must(reviewers).keys.to_h { |k| [k.to_sym, T.must(reviewers)[k]] }
        reviewers = []
        reviewers += reviewers_hash[:reviewers] || []
        reviewers += (reviewers_hash[:team_reviewers] || [])
                     .map { |rv| "#{source.repo.split('/').first}/#{rv}" }

        reviewers_string =
          if reviewers.count == 1
            "`@#{reviewers.first}`"
          else
            names = reviewers.map { |rv| "`@#{rv}`" }
            "#{T.must(names[0..-2]).join(', ')} and #{names[-1]}"
          end

        msg = "Dependabot tried to add #{reviewers_string} as "
        msg += reviewers.count > 1 ? "reviewers" : "a reviewer"
        msg += " to this PR, but received the following error from GitHub:\n\n" \
               "```\n" \
               "#{message}\n" \
               "```"

        T.unsafe(github_client_for_source).add_comment(
          source.repo,
          pull_request.number,
          msg
        )
      end

      sig { params(pull_request: T.untyped).void }
      def add_assignees_to_pull_request(pull_request)
        T.unsafe(github_client_for_source).add_assignees(
          source.repo,
          pull_request.number,
          assignees
        )
      rescue Octokit::NotFound
        # This can happen if a passed assignee login is now an org account
        nil
      rescue Octokit::UnprocessableEntity => e
        # This can happen if an invalid assignee was passed
        raise unless e.message.include?("Could not add assignees")
      end

      sig { params(pull_request: T.untyped).void }
      def add_milestone_to_pull_request(pull_request)
        T.unsafe(github_client_for_source).update_issue(
          source.repo,
          pull_request.number,
          milestone: milestone
        )
      rescue Octokit::UnprocessableEntity => e
        raise unless e.message.include?("code: invalid")
      end

      sig { returns(T.untyped) }
      def create_pull_request
        T.unsafe(github_client_for_source).create_pull_request(
          source.repo,
          target_branch,
          branch_name,
          pr_name,
          pr_description,
          headers: custom_headers || {}
        )
      rescue Octokit::UnprocessableEntity
        # Sometimes PR creation fails with no details (presumably because the
        # details are internal). It doesn't hurt to retry in these cases, in
        # case the cause is a race.
        retrying_pr_creation ||= T.let(false, T::Boolean)
        raise if retrying_pr_creation

        retrying_pr_creation = true
        retry
      end

      sig { returns(String) }
      def target_branch
        source.branch || default_branch
      end

      sig { returns(String) }
      def default_branch
        @default_branch ||=
          T.let(
            T.unsafe(github_client_for_source).repo(source.repo).default_branch,
            T.nilable(String)
          )
      end

      sig { returns(Dependabot::GitMetadataFetcher) }
      def git_metadata_fetcher
        @git_metadata_fetcher ||=
          T.let(
            GitMetadataFetcher.new(
              url: source.url,
              credentials: credentials
            ),
            T.nilable(Dependabot::GitMetadataFetcher)
          )
      end

      sig do
        params(tree: T.untyped, author_details_with_date: T::Hash[Symbol, String]).returns(String)
      end
      def commit_signature(tree, author_details_with_date)
        CommitSigner.new(
          author_details: author_details_with_date,
          commit_message: commit_message,
          tree_sha: tree.sha,
          parent_sha: base_commit,
          signature_key: T.must(signature_key)
        ).signature
      end

      sig { params(counter: T.nilable(Integer), limit: Integer).void }
      def raise_or_increment_retry_counter(counter:, limit:)
        counter ||= 0
        counter += 1
        raise if counter > limit
      end

      sig { returns(Dependabot::Clients::GithubWithRetries) }
      def github_client_for_source
        @github_client_for_source ||=
          T.let(
            Dependabot::Clients::GithubWithRetries.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::GithubWithRetries)
          )
      end

      sig { params(err: StandardError).returns(T.noreturn) }
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

      sig { params(base_err: StandardError, type: T.class_of(StandardError), message: String).returns(T.noreturn) }
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
  end
end
