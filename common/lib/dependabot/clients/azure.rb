# frozen_string_literal: true

require "dependabot/shared_helpers"
require "excon"
require "cgi"

module Dependabot
  module Clients
    class Azure
      class NotFound < StandardError; end

      class InternalServerError < StandardError; end

      class ServiceNotAvailable < StandardError; end

      class BadGateway < StandardError; end

      class Unauthorized < StandardError; end

      class Forbidden < StandardError; end

      class TagsCreationForbidden < StandardError; end

      RETRYABLE_ERRORS = [InternalServerError, BadGateway, ServiceNotAvailable].freeze

      MAX_PR_DESCRIPTION_LENGTH = 3999

      #######################
      # Constructor methods #
      #######################

      def self.for_source(source:, credentials:)
        credential =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == source.hostname }
        new(source, credential)
      end

      ##########
      # Client #
      ##########

      def initialize(source, credentials, max_retries: 3)
        @source = source
        @credentials = credentials
        @auth_header = auth_header_for(credentials&.fetch("token", nil))
        @max_retries = max_retries || 3
      end

      def fetch_commit(_repo, branch)
        response = get(source.api_endpoint +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/stats/branches?name=" + branch)

        raise NotFound if response.status == 400

        JSON.parse(response.body).fetch("commit").fetch("commitId")
      end

      def fetch_default_branch(_repo)
        response = get(source.api_endpoint +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo)

        JSON.parse(response.body).fetch("defaultBranch").gsub("refs/heads/", "")
      end

      def fetch_repo_contents(commit = nil, path = nil)
        tree = fetch_repo_contents_treeroot(commit, path)

        response = get(source.api_endpoint +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/trees/" + tree + "?recursive=false")

        JSON.parse(response.body).fetch("treeEntries")
      end

      def fetch_repo_contents_treeroot(commit = nil, path = nil)
        actual_path = path
        actual_path = "/" if path.to_s.empty?

        tree_url = source.api_endpoint +
                   source.organization + "/" + source.project +
                   "/_apis/git/repositories/" + source.unscoped_repo +
                   "/items?path=" + actual_path

        unless commit.to_s.empty?
          tree_url += "&versionDescriptor.versionType=commit" \
                      "&versionDescriptor.version=" + commit
        end

        tree_response = get(tree_url)

        JSON.parse(tree_response.body).fetch("objectId")
      end

      def fetch_file_contents(commit, path)
        response = get(source.api_endpoint +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/items?path=" + path +
          "&versionDescriptor.versionType=commit" \
          "&versionDescriptor.version=" + commit)

        response.body
      end

      def commits(branch_name = nil)
        commits_url = source.api_endpoint +
                      source.organization + "/" + source.project +
                      "/_apis/git/repositories/" + source.unscoped_repo +
                      "/commits"

        commits_url += "?searchCriteria.itemVersion.version=" + branch_name unless branch_name.to_s.empty?

        response = get(commits_url)

        JSON.parse(response.body).fetch("value")
      end

      def branch(branch_name)
        response = get(source.api_endpoint +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/refs?filter=heads/" + branch_name)

        JSON.parse(response.body).fetch("value").first
      end

      def pull_requests(source_branch, target_branch)
        response = get(source.api_endpoint +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/pullrequests?searchCriteria.status=all" \
          "&searchCriteria.sourceRefName=refs/heads/" + source_branch +
          "&searchCriteria.targetRefName=refs/heads/" + target_branch)

        JSON.parse(response.body).fetch("value")
      end

      # rubocop:disable Metrics/AbcSize
      def fetch_repo_paths_for_code_search(search_text, directory)
        code_paths = []
        current_page_number = 1
        page_limit = 1000

        # If Dependabot::Source object is initialized with project/repo id(instead of name)
        # Need to fetch the project and repo name since code search API project/repo filters do not work with ids.
        repo_details = repository_details
        repo_project_name = repo_details.fetch("project").fetch("name")
        repo_name = repo_details.fetch("name")
        # API documentation link: https://docs.microsoft.com/en-us/rest/api/azure/devops/search/code-search-results/fetch-code-search-results?view=azure-devops-rest-6.0
        # This is a paginated API with page limit of 1000 records
        # Hence we need to call the API iteratively for each page of records until all records are received.
        loop do
          content = {
            searchText: search_text,
            "$skip": (current_page_number - 1) * page_limit,
            "$top": page_limit,
            "$orderBy": [
              {
                field: "path",
                sortOrder: "ASC"
              }
            ],
            filters: {
              Project: [CGI.unescape(repo_project_name)],
              Repository: [CGI.unescape(repo_name)],
              Path: [directory],
              Branch: [source.branch]
            }
          }

          response = post("https://almsearch.dev.azure.com/" + source.organization + "/" + source.project +
            "/_apis/search/codesearchresults?api-version=6.0", content.to_json)

          response_json = JSON.parse(response.body)

          raise BadRequest, response_json.fetch("message") if response.status == 400

          total_result_count = response_json.fetch("count").to_i
          response_json.fetch("results").each { |result| code_paths.append(result.fetch("path")) }

          break if total_result_count <= current_page_number * page_limit

          current_page_number += 1
        end

        code_paths
      end
      # rubocop:enable Metrics/AbcSize

      def repository_details
        @repository_details ||=
          begin
            response = get(source.api_endpoint +
              source.organization + "/" + source.project +
              "/_apis/git/repositories/" + source.unscoped_repo +
              "?api-version=6.0")

            JSON.parse(response.body)
          end
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
                  changeType: file_exists?(base_commit, file.path) ? "edit" : "add",
                  item: { path: file.path },
                  newContent: {
                    content: Base64.encode64(file.content),
                    contentType: "base64encoded"
                  }
                }
              end
            }.compact
          ]
        }

        post(source.api_endpoint + source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/pushes?api-version=5.0", content.to_json)
      end

      # rubocop:disable Metrics/ParameterLists
      def create_pull_request(pr_name, source_branch, target_branch,
                              pr_description, labels, work_item = nil)
        pr_description = truncate_pr_description(pr_description)

        content = {
          sourceRefName: "refs/heads/" + source_branch,
          targetRefName: "refs/heads/" + target_branch,
          title: pr_name,
          description: pr_description,
          labels: labels.map { |label| { name: label } },
          workItemRefs: [{ id: work_item }]
        }

        post(source.api_endpoint +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/pullrequests?api-version=5.0", content.to_json)
      end

      def pull_request(pull_request_id)
        response = get(source.api_endpoint +
          source.organization + "/" + source.project +
          "/_apis/git/pullrequests/" + pull_request_id)

        JSON.parse(response.body)
      end

      def update_ref(branch_name, old_commit, new_commit)
        content = [
          {
            name: "refs/heads/" + branch_name,
            oldObjectId: old_commit,
            newObjectId: new_commit
          }
        ]

        response = post(source.api_endpoint + source.organization + "/" + source.project +
                        "/_apis/git/repositories/" + source.unscoped_repo +
                        "/refs?api-version=5.0", content.to_json)

        JSON.parse(response.body).fetch("value").first
      end
      # rubocop:enable Metrics/ParameterLists

      def get(url)
        response = nil

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

        raise Unauthorized if response.status == 401
        raise Forbidden if response.status == 403
        raise NotFound if response.status == 404

        response
      end

      def post(url, json)
        response = nil

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

          raise InternalServerError if response.status == 500
          raise BadGateway if response.status == 502
          raise ServiceNotAvailable if response.status == 503
        end

        raise Unauthorized if response.status == 401

        if response.status == 403
          raise TagsCreationForbidden if tags_creation_forbidden?(response)

          raise Forbidden
        end
        raise NotFound if response.status == 404

        response
      end

      private

      def retry_connection_failures
        retry_attempt = 0

        begin
          yield
        rescue *RETRYABLE_ERRORS
          retry_attempt += 1
          retry_attempt <= @max_retries ? retry : raise
        end
      end

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

      def file_exists?(commit, path)
        # Get the file base and directory name
        dir = File.dirname(path)
        basename = File.basename(path)

        # Fetch the contents for the dir and check if there exists any file that matches basename.
        # We ignore any sub-dir paths by rejecting "tree" gitObjectType (which is what ADO uses to specify a directory.)
        fetch_repo_contents(commit, dir).
          reject { |f| f["gitObjectType"] == "tree" }.
          one? { |f| f["relativePath"] == basename }
      rescue Dependabot::Clients::Azure::NotFound
        # ADO throws exception if dir not found. Return false
        false
      end

      def truncate_pr_description(pr_description)
        # Azure DevOps only support descriptions up to 4000 characters in UTF-16
        # encoding.
        # https://developercommunity.visualstudio.com/content/problem/608770/remove-4000-character-limit-on-pull-request-descri.html
        pr_description = pr_description.dup.force_encoding(Encoding::UTF_16)
        if pr_description.length > MAX_PR_DESCRIPTION_LENGTH
          truncated_msg = "...\n\n_Description has been truncated_".dup.force_encoding(Encoding::UTF_16)
          truncate_length = MAX_PR_DESCRIPTION_LENGTH - truncated_msg.length
          pr_description = (pr_description[0..truncate_length] + truncated_msg)
        end
        pr_description.force_encoding(Encoding::UTF_8)
      end

      def tags_creation_forbidden?(response)
        return if response.body.empty?

        message = JSON.parse(response.body).fetch("message", nil)
        message&.include?("TF401289")
      end

      attr_reader :auth_header
      attr_reader :credentials
      attr_reader :source
    end
  end
end
