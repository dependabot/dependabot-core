# frozen_string_literal: true

require "dependabot/shared_helpers"
require "excon"

module Dependabot
  module Clients
    class BitbucketServer
      class NotFound < StandardError; end

      class Unauthorized < StandardError; end

      class Forbidden < StandardError; end

      ##########
      # Client #
      ##########

      def initialize(credentials:, source:)
        @credentials = credentials
        @source = source
        @auth_header = SharedHelpers.auth_header_for(credentials&.fetch("token", nil))
      end

      def fetch_commit(repo, branch)
        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp225
        path = "projects/#{@source.namespace}/repos/#{repo}/commits/#{branch}"
        response = get(base_url + path)
        JSON.parse(response.body).fetch("id")
      end

      def fetch_default_branch(repo)
        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp213
        path = "projects/#{@source.namespace}/repos/#{repo}/branches/default"
        response = get(base_url + path)
        JSON.parse(response.body).fetch("id").sub("refs/heads/", "")
      end

      def fetch_repo_contents(repo, commit = nil, path = nil)
        raise "Commit is required if path provided!" if commit.nil? && path

        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp216
        api_path = "projects/#{@source.namespace}/repos/#{repo}/browse?at=#{commit}&limit=100"
        response = get(base_url + api_path)
        JSON.parse(response.body).fetch("children").fetch("values")
      end

      def fetch_file_contents(repo, commit, path)
        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp362
        path = "projects/#{@source.namespace}/repos/#{repo}/raw/#{path}?at=#{commit}"
        response = get(base_url + path)

        response.body
      end

      def commits(repo, branch_name = nil)
        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp222
        commits_path = "projects/#{@source.namespace}/repos/#{repo}/commits?since=#{branch_name}&limit=100"
        next_page_url = base_url + commits_path
        paginate({ "next" => next_page_url })
      end

      def branch(repo, branch_name)
        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp209
        branch_path = "projects/#{@source.namespace}/repos/#{repo}/branches?filterText=#{branch_name}"
        response = get(base_url + branch_path)
        branches = JSON.parse(response.body).fetch("values")

        raise "More then one branches found" if branches.length > 1

        branches.first
      end

      def pull_requests(repo, source_branch, target_branch)
        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp294
        pr_path = "projects/#{@source.namespace}/repos/#{repo}/pull-requests?state=ALL"
        next_page_url = base_url + pr_path
        pull_requests = paginate({ "next" => next_page_url })

        pull_requests unless source_branch && target_branch

        pull_requests.select do |pr|
          pr_source_branch = pr.fetch("fromRef").fetch("id").sub("refs/heads/", "")
          pr_target_branch = pr.fetch("toRef").fetch("id").sub("refs/heads/", "")

          pr_source_branch == source_branch && pr_target_branch == target_branch
        end
      end

      # rubocop:disable Metrics/ParameterLists
      def create_commit(repo, branch_name, base_commit, commit_message, files, author_details)
        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp218
        branch = self.branch(repo, branch_name)
        if branch.nil?
          source_branch = self.fetch_default_branch(repo)
          source_commit_id = base_commit
        else
          source_branch = branch_name;
          source_commit_id = branch.fetch("latestCommit")
        end

        files.each do |file|
          multipart_data = SharedHelpers.excon_multipart_form_data(
            {
              message: commit_message, # TODO: Format markup in commit message
              branch: branch_name,
              sourceCommitId: source_commit_id,
              content: file.content,
              sourceBranch: source_branch
            }
          )

          commit_path = "projects/#{@source.namespace}/repos/#{repo}/browse/#{file.name}"
          response = put(base_url + commit_path, multipart_data.fetch('body'), multipart_data.fetch('header_value'))

          brand_details = JSON.parse(response.body)
          next if brand_details.fetch("errors", []).length > 0

          source_commit_id = brand_details.fetch("id")
          source_branch = brand_details.fetch("displayId")
        end
      end

      # rubocop:enable Metrics/ParameterLists

      # rubocop:disable Metrics/ParameterLists
      def create_pull_request(repo, pr_name, source_branch, target_branch,
                              pr_description, _labels, _work_item = nil)
        content = {
          title: pr_name,
          description: pr_description,
          state: "OPEN",
          fromRef: {
            id: source_branch
          },
          toRef: {
            id: target_branch
          }
        }

        pr_path = "projects/#{@source.namespace}/repos/#{repo}/pull-requests"
        post(base_url + pr_path, content.to_json)
      end

      # rubocop:enable Metrics/ParameterLists
      def tags(repo)
        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp398
        raise "Not tested"

        path = "projects/#{@source.namespace}/repos/#{repo}/tags?limit=100"
        response = get(base_url + path)

        JSON.parse(response.body).fetch("values")
      end

      def compare(repo, previous_tag, new_tag)
        raise "Not tested"

        # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp398
        path = "projects/#{@source.namespace}/repos/#{repo}/compare/changes?from=#{previous_tag}&to=#{new_tag}"
        response = get(base_url + path)

        JSON.parse(response.body).fetch("values")
      end

      def get(url)
        make_request("get", url, nil, "application/json")
      end

      def post(url, body, content_type = "application/json")
        make_request("post", url, body, content_type)
      end

      def put(url, body, content_type = "application/json")
        make_request("put", url, body, content_type)
      end

      private

      def make_request(method, url, body = nil, content_type = "application/json")
        response = Excon.method(method).call(
          url,
          body: body,
          user: credentials&.fetch("username", nil),
          password: credentials&.fetch("password", nil),
          idempotent: false,
          **SharedHelpers.excon_defaults(
            headers: auth_header.merge(
              {
                "Content-Type" => content_type
              }
            )
          )
        )
        raise Unauthorized if response.status == 401
        raise Forbidden if response.status == 403
        raise NotFound if response.status == 404

        response
      end

      # Takes a hash with optional `values` and `next` fields
      # Returns an enumerator.
      #
      # Can be used a few ways:
      # With GET:
      #     paginate ({"next" => url})
      # or
      #     paginate(JSON.parse(get(url).body))
      #
      # With POST (for endpoints that provide POST methods for long query parameters)
      #     response = post(url, body)
      #     first_page = JSON.parse(repsonse.body)
      #     paginate(first_page)
      def paginate(page)
        start = 0
        limit = 100
        Enumerator.new do |yielder|
          loop do
            page.fetch("values", []).each { |value| yielder << value }
            break if page.fetch("isLastPage", false)

            uri = URI(page.fetch("next"))
            uri.query = [uri.query, "start=#{start}&limit=#{limit}"].compact.join('&')
            next_page_url = uri.to_s

            page = JSON.parse(get(next_page_url).body)
            if page.key?("nextPageStart") and page.fetch("nextPageStart") != nil
              start = page.fetch("nextPageStart");
            end
          end
        end
      end

      attr_reader :auth_header
      attr_reader :credentials

      def base_url
        uri = URI(@source.api_endpoint)
        uri.path = uri.path + (uri.path.end_with?("/") ? '' : '/')
        uri.to_s
      end
    end
  end
end
