# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "excon"
require "sorbet-runtime"

module Dependabot
  module Clients
    # rubocop:disable Metrics/ClassLength
    class Azure
      extend T::Sig

      class NotFound < StandardError; end

      class InternalServerError < StandardError; end

      class ServiceNotAvailable < StandardError; end

      class BadGateway < StandardError; end

      class Unauthorized < StandardError; end

      class Forbidden < StandardError; end

      class TagsCreationForbidden < StandardError; end

      RETRYABLE_ERRORS = T.let(
        [InternalServerError, BadGateway, ServiceNotAvailable].freeze,
        T::Array[T.class_of(StandardError)]
      )

      #######################
      # Constructor methods #
      #######################

      sig { params(source: Dependabot::Source, credentials: T::Array[Dependabot::Credential]).returns(Azure) }
      def self.for_source(source:, credentials:)
        credential =
          credentials
          .select { |cred| cred["type"] == "git_source" }
          .find { |cred| cred["host"] == source.hostname }

        new(source, credential)
      end

      ##########
      # Client #
      ##########

      sig do
        params(
          source: Dependabot::Source,
          credentials: T.nilable(Dependabot::Credential),
          max_retries: T.nilable(Integer)
        )
          .void
      end
      def initialize(source, credentials, max_retries: 3)
        @source = source
        @credentials = credentials
        @auth_header = T.let(auth_header_for(credentials&.fetch("token", nil)), T::Hash[String, String])
        @max_retries = T.let(max_retries || 3, Integer)
      end

      sig { params(_repo: T.nilable(String), branch: String).returns(String) }
      def fetch_commit(_repo, branch)
        response = get(T.must(source.api_endpoint) +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/stats/branches?name=" + branch)

        raise NotFound if response.status == 400

        JSON.parse(response.body).fetch("commit").fetch("commitId")
      end

      sig { params(_repo: String).returns(String) }
      def fetch_default_branch(_repo)
        response = get(T.must(source.api_endpoint) +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo)

        JSON.parse(response.body).fetch("defaultBranch").gsub("refs/heads/", "")
      end

      sig do
        params(
          commit: T.nilable(String),
          path: T.nilable(String)
        )
          .returns(T::Array[T::Hash[String, T.untyped]])
      end
      def fetch_repo_contents(commit = nil, path = nil)
        tree = fetch_repo_contents_treeroot(commit, path)

        response = get(T.must(source.api_endpoint) +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/trees/" + tree + "?recursive=false")

        JSON.parse(response.body).fetch("treeEntries")
      end

      sig { params(commit: T.nilable(String), path: T.nilable(String)).returns(String) }
      def fetch_repo_contents_treeroot(commit = nil, path = nil)
        actual_path = path
        actual_path = "/" if path.to_s.empty?

        tree_url = T.must(source.api_endpoint) +
                   source.organization + "/" + source.project +
                   "/_apis/git/repositories/" + source.unscoped_repo +
                   "/items?path=" + T.must(actual_path)

        unless commit.to_s.empty?
          tree_url += "&versionDescriptor.versionType=commit" \
                      "&versionDescriptor.version=" + T.must(commit)
        end

        tree_response = get(tree_url)

        JSON.parse(tree_response.body).fetch("objectId")
      end

      sig { params(commit: String, path: String).returns(String) }
      def fetch_file_contents(commit, path)
        response = get(T.must(source.api_endpoint) +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/items?path=" + path +
          "&versionDescriptor.versionType=commit" \
          "&versionDescriptor.version=" + commit)

        response.body
      end

      sig { params(branch_name: T.nilable(String)).returns(T::Array[T::Hash[String, T.untyped]]) }
      def commits(branch_name = nil)
        commits_url = T.must(source.api_endpoint) +
                      source.organization + "/" + source.project +
                      "/_apis/git/repositories/" + source.unscoped_repo +
                      "/commits"

        commits_url += "?searchCriteria.itemVersion.version=" + T.must(branch_name) unless branch_name.to_s.empty?

        response = get(commits_url)

        JSON.parse(response.body).fetch("value")
      end

      sig { params(branch_name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def branch(branch_name)
        response = get(T.must(source.api_endpoint) +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/refs?filter=heads/" + branch_name)

        JSON.parse(response.body).fetch("value").first
      end

      sig { params(source_branch: String, target_branch: String).returns(T::Array[T::Hash[String, T.untyped]]) }
      def pull_requests(source_branch, target_branch)
        response = get(T.must(source.api_endpoint) +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/pullrequests?searchCriteria.status=all" \
          "&searchCriteria.sourceRefName=refs/heads/" + source_branch +
          "&searchCriteria.targetRefName=refs/heads/" + target_branch)

        JSON.parse(response.body).fetch("value")
      end

      sig do
        params(
          branch_name: String,
          base_commit: String,
          commit_message: String,
          files: T::Array[Dependabot::DependencyFile],
          author_details: T.nilable(T::Hash[String, String])
        )
          .returns(T.untyped)
      end
      def create_commit(branch_name, base_commit, commit_message, files,
                        author_details)
        content = {
          refUpdates: [
            { name: "refs/heads/" + branch_name, oldObjectId: base_commit }
          ],
          commits: [
            {
              comment: commit_message,
              author: author_details,
              changes: files.map do |file|
                {
                  changeType: "edit",
                  item: { path: file.path },
                  newContent: {
                    content: Base64.encode64(T.must(file.content)),
                    contentType: "base64encoded"
                  }
                }
              end
            }.compact
          ]
        }

        post(T.must(source.api_endpoint) + source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/pushes?api-version=5.0", content.to_json)
      end

      # rubocop:disable Metrics/ParameterLists
      sig do
        params(
          pr_name: String,
          source_branch: String,
          target_branch: String,
          pr_description: String,
          labels: T::Array[String],
          reviewers: T.nilable(T::Array[String]),
          assignees: T.nilable(T::Array[String]),
          work_item: T.nilable(Integer)
        )
          .returns(T.untyped)
      end
      def create_pull_request(pr_name, source_branch, target_branch,
                              pr_description, labels,
                              reviewers = nil, assignees = nil, work_item = nil)

        content = {
          sourceRefName: "refs/heads/" + source_branch,
          targetRefName: "refs/heads/" + target_branch,
          title: pr_name,
          description: pr_description,
          labels: labels.map { |label| { name: label } },
          reviewers: pr_reviewers(reviewers, assignees),
          workItemRefs: [{ id: work_item }]
        }

        post(T.must(source.api_endpoint) +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/pullrequests?api-version=5.0", content.to_json)
      end

      sig do
        params(
          pull_request_id: Integer,
          auto_complete_set_by: String,
          merge_commit_message: String,
          delete_source_branch: T::Boolean,
          squash_merge: T::Boolean,
          merge_strategy: String,
          trans_work_items: T::Boolean,
          ignore_config_ids: T::Array[String]
        )
          .returns(T.untyped)
      end
      def autocomplete_pull_request(pull_request_id, auto_complete_set_by, merge_commit_message,
                                    delete_source_branch = true, squash_merge = true, merge_strategy = "squash",
                                    trans_work_items = true, ignore_config_ids = [])

        content = {
          autoCompleteSetBy: {
            id: auto_complete_set_by
          },
          completionOptions: {
            mergeCommitMessage: merge_commit_message,
            deleteSourceBranch: delete_source_branch,
            squashMerge: squash_merge,
            mergeStrategy: merge_strategy,
            transitionWorkItems: trans_work_items,
            autoCompleteIgnoreConfigIds: ignore_config_ids
          }
        }

        response = patch(T.must(source.api_endpoint) +
                           source.organization + "/" + source.project +
                           "/_apis/git/repositories/" + source.unscoped_repo +
                           "/pullrequests/" + pull_request_id.to_s + "?api-version=5.1", content.to_json)

        JSON.parse(response.body)
      end

      sig { params(pull_request_id: String).returns(T::Hash[String, T.untyped]) }
      def pull_request(pull_request_id)
        response = get(T.must(source.api_endpoint) +
          source.organization + "/" + source.project +
          "/_apis/git/pullrequests/" + pull_request_id)

        JSON.parse(response.body)
      end

      sig { params(branch_name: String, old_commit: String, new_commit: String).returns(T::Hash[String, T.untyped]) }
      def update_ref(branch_name, old_commit, new_commit)
        content = [
          {
            name: "refs/heads/" + branch_name,
            oldObjectId: old_commit,
            newObjectId: new_commit
          }
        ]

        response = post(T.must(source.api_endpoint) + source.organization + "/" + source.project +
                        "/_apis/git/repositories/" + source.unscoped_repo +
                        "/refs?api-version=5.0", content.to_json)

        JSON.parse(response.body).fetch("value").first
      end
      # rubocop:enable Metrics/ParameterLists

      sig do
        params(
          previous_tag: T.nilable(String), new_tag: T.nilable(String),
          type: String
        )
          .returns(T::Array[T::Hash[String, T.untyped]])
      end
      def compare(previous_tag, new_tag, type)
        response = get(T.must(source.api_endpoint) +
                         source.organization + "/" + source.project +
                         "/_apis/git/repositories/" + source.unscoped_repo +
                         "/commits?searchCriteria.itemVersion.versionType=#{type}" \
                         "&searchCriteria.itemVersion.version=#{previous_tag}" \
                         "&searchCriteria.compareVersion.versionType=#{type}" \
                         "&searchCriteria.compareVersion.version=#{new_tag}")

        JSON.parse(response.body).fetch("value")
      end

      sig { params(url: String).returns(Excon::Response) }
      def get(url)
        response = T.let(nil, T.nilable(Excon::Response))

        retry_connection_failures do
          response = Excon.get(
            url,
            user: credentials&.fetch("username", nil),
            password: credentials&.fetch("password", nil),
            idempotent: true,
            **SharedHelpers.excon_defaults(
              headers: auth_header
            )
          )

          raise InternalServerError if response.status == 500
          raise BadGateway if response.status == 502
          raise ServiceNotAvailable if response.status == 503
        end

        raise Unauthorized if response&.status == 401
        raise Forbidden if response&.status == 403
        raise NotFound if response&.status == 404

        T.must(response)
      end

      sig { params(url: String, json: String).returns(Excon::Response) }
      def post(url, json) # rubocop:disable Metrics/PerceivedComplexity
        response = T.let(nil, T.nilable(Excon::Response))

        retry_connection_failures do
          response = Excon.post(
            url,
            body: json,
            user: credentials&.fetch("username", nil),
            password: credentials&.fetch("password", nil),
            idempotent: true,
            **SharedHelpers.excon_defaults(
              headers: auth_header.merge(
                {
                  "Content-Type" => "application/json"
                }
              )
            )
          )

          raise InternalServerError if response&.status == 500
          raise BadGateway if response&.status == 502
          raise ServiceNotAvailable if response&.status == 503
        end

        raise Unauthorized if response&.status == 401

        if response&.status == 403
          raise TagsCreationForbidden if tags_creation_forbidden?(T.must(response))

          raise Forbidden
        end
        raise NotFound if response&.status == 404

        T.must(response)
      end

      sig { params(url: String, json: String).returns(Excon::Response) }
      def patch(url, json)
        response = T.let(nil, T.nilable(Excon::Response))

        retry_connection_failures do
          response = Excon.patch(
            url,
            body: json,
            user: credentials&.fetch("username", nil),
            password: credentials&.fetch("password", nil),
            idempotent: true,
            **SharedHelpers.excon_defaults(
              headers: auth_header.merge(
                {
                  "Content-Type" => "application/json"
                }
              )
            )
          )

          raise InternalServerError if response&.status == 500
          raise BadGateway if response&.status == 502
          raise ServiceNotAvailable if response&.status == 503
        end

        raise Unauthorized if response&.status == 401
        raise Forbidden if response&.status == 403
        raise NotFound if response&.status == 404

        T.must(response)
      end

      private

      sig { params(blk: T.proc.void).void }
      def retry_connection_failures(&blk) # rubocop:disable Lint/UnusedMethodArgument
        retry_attempt = 0

        begin
          yield
        rescue *RETRYABLE_ERRORS
          retry_attempt += 1
          retry_attempt <= @max_retries ? retry : raise
        end
      end

      sig { params(token: T.nilable(String)).returns(T::Hash[String, String]) }
      def auth_header_for(token)
        return {} unless token

        if token.include?(":")
          encoded_token = Base64.encode64(token).delete("\n")
          { "Authorization" => "Basic #{encoded_token}" }
        elsif Base64.decode64(token).ascii_only? &&
              Base64.decode64(token).include?(":")
          { "Authorization" => "Basic #{token.delete("\n")}" }
        else
          { "Authorization" => "Bearer #{token}" }
        end
      end

      sig { params(response: Excon::Response).returns(T::Boolean) }
      def tags_creation_forbidden?(response)
        return false if response.body.empty?

        message = JSON.parse(response.body).fetch("message", nil)
        message&.include?("TF401289")
      end

      sig do
        params(
          reviewers: T.nilable(T::Array[String]),
          assignees: T.nilable(T::Array[String])
        )
          .returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def pr_reviewers(reviewers, assignees)
        return [] unless reviewers || assignees

        pr_reviewers = reviewers&.map { |r_id| { id: r_id, isRequired: true } } || []
        pr_reviewers + (assignees&.map { |r_id| { id: r_id, isRequired: false } } || [])
      end

      sig { returns(T::Hash[String, String]) }
      attr_reader :auth_header

      sig { returns(T.nilable(Dependabot::Credential)) }
      attr_reader :credentials

      sig { returns(Dependabot::Source) }
      attr_reader :source
    end
    # rubocop:enable Metrics/ClassLength
  end
end
