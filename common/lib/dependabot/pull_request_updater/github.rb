# typed: strict
# frozen_string_literal: true

require "octokit"
require "sorbet-runtime"

require "dependabot/clients/github_with_retries"
require "dependabot/pull_request_creator/commit_signer"
require "dependabot/pull_request_updater"

module Dependabot
  class PullRequestUpdater
    class Github
      extend T::Sig

      sig { returns(Dependabot::Source) }
      attr_reader :source

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :files

      sig { returns(String) }
      attr_reader :base_commit

      sig { returns(String) }
      attr_reader :old_commit

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(Integer) }
      attr_reader :pull_request_number

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      attr_reader :author_details

      sig { returns(T.nilable(String)) }
      attr_reader :signature_key

      sig do
        params(
          source: Dependabot::Source,
          base_commit: String,
          old_commit: String,
          files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          pull_request_number: Integer,
          author_details: T.nilable(T::Hash[Symbol, T.untyped]),
          signature_key: T.nilable(String)
        )
          .void
      end
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

      sig { returns(T.nilable(Sawyer::Resource)) }
      def update
        return unless pull_request_exists?
        return unless branch_exists?(pull_request.head.ref)

        commit = create_commit
        branch = update_branch(commit)
        update_pull_request_target_branch
        branch
      end

      private

      sig { void }
      def update_pull_request_target_branch
        target_branch = source.branch || pull_request.base.repo.default_branch
        return if target_branch == pull_request.base.ref

        T.unsafe(github_client_for_source).update_pull_request(
          source.repo,
          pull_request_number,
          base: target_branch
        )
      rescue Octokit::UnprocessableEntity => e
        handle_pr_update_error(e)
      end

      sig { params(error: Octokit::Error).void }
      def handle_pr_update_error(error)
        # Return quietly if the PR has been closed
        return if error.message.match?(/closed pull request/i)

        # Ignore cases where the target branch has been deleted
        return if error.message.include?("field: base") &&
                  source.branch &&
                  !branch_exists?(T.must(source.branch))

        raise error
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

      sig { returns(T::Boolean) }
      def pull_request_exists?
        pull_request
        true
      rescue Octokit::NotFound
        false
      end

      sig { returns(T.untyped) }
      def pull_request
        @pull_request ||=
          T.let(
            T.unsafe(github_client_for_source).pull_request(
              source.repo,
              pull_request_number
            ),
            T.untyped
          )
      end

      sig { params(name: String).returns(T::Boolean) }
      def branch_exists?(name)
        T.unsafe(github_client_for_source).branch(source.repo, name)
        true
      rescue Octokit::NotFound
        false
      end

      sig { returns(T.untyped) }
      def create_commit
        tree = create_tree

        options = author_details&.any? ? { author: author_details } : {}

        if options[:author]&.any? && signature_key
          options[:author][:date] = Time.now.utc.iso8601
          options[:signature] = commit_signature(tree, options[:author])
        end

        begin
          T.unsafe(github_client_for_source).create_commit(
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
              mode: Dependabot::DependencyFile::Mode::FILE,
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

      BRANCH_PROTECTION_ERROR_MESSAGES = T.let(
        [
          /protected branch/i,
          /not authorized to push/i,
          /must not contain merge commits/i,
          /required status check/i,
          /cannot force-push to this branch/i,
          /pull request for this branch has been added to a merge queue/i,
          # Unverified commits can be present when PR contains commits from other authors
          /commits must have verified signatures/i,
          /changes must be made through a pull request/i,
        ],
        T::Array[Regexp]
      )

      sig { params(commit: T.untyped).returns(T.untyped) }
      def update_branch(commit)
        T.unsafe(github_client_for_source).update_ref(
          source.repo,
          "heads/" + pull_request.head.ref,
          commit.sha,
          true
        )
      rescue Octokit::UnprocessableEntity => e
        # Return quietly if the branch has been deleted or merged
        return nil if e.message.match?(/Reference does not exist/i)
        return nil if e.message.match?(/Reference cannot be updated/i)

        raise BranchProtected, e.message if BRANCH_PROTECTION_ERROR_MESSAGES.any? { |msg| e.message.match?(msg) }

        raise
      end

      sig { returns(String) }
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

      sig { returns(T.untyped) }
      def commit_being_updated
        return @commit_being_updated if defined?(@commit_being_updated)

        @commit_being_updated =
          T.let(
            if pull_request.commits == 1
              T.unsafe(github_client_for_source)
               .git_commit(source.repo, pull_request.head.sha)
            else
              commits =
                T.unsafe(github_client_for_source)
                 .pull_request_commits(source.repo, pull_request_number)

              commit = commits.find { |c| c.sha == old_commit }
              commit&.commit
            end,
            T.untyped
          )
      end

      sig { params(tree: T.untyped, author_details_with_date: T::Hash[Symbol, T.untyped]).returns(String) }
      def commit_signature(tree, author_details_with_date)
        PullRequestCreator::CommitSigner.new(
          author_details: author_details_with_date,
          commit_message: commit_message,
          tree_sha: tree.sha,
          parent_sha: base_commit,
          signature_key: T.must(signature_key)
        ).signature
      end
    end
  end
end
