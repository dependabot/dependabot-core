# frozen_string_literal: true

require "dependabot/shared_helpers"
require "excon"

module Dependabot
  module Clients
    class Bitbucket
      class NotFound < StandardError; end

      class Unauthorized < StandardError; end

      class Forbidden < StandardError; end

      #######################
      # Constructor methods #
      #######################

      def self.for_source(source:, credentials:)
        credential =
          credentials.
            select { |cred| cred["type"] == "git_source" }.
            find { |cred| cred["host"] == source.hostname }

        new(source: source, credentials: credential)
      end

      ##########
      # Client #
      ##########

      def initialize(source:, credentials:)
        @source = source
        @credentials = credentials
        @auth_header = auth_header_for(credentials&.fetch("token", nil))
      end

      def fetch_commit(repo, branch)
        if @source.provider == "bitbucket_server"
          # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp225
          path = "projects/#{@source.namespace}/repos/#{repo}/commits/#{branch}"
          response = get(base_url + path)
          JSON.parse(response.body).fetch("id")
        else
          path = "#{repo}/refs/branches/#{branch}"
          response = get(base_url + path)
          JSON.parse(response.body).fetch("target").fetch("hash")
        end
      end

      def fetch_default_branch(repo)
        if @source.provider == "bitbucket_server"
          # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp213
          path = "projects/#{@source.namespace}/repos/#{repo}/branches/default"
          response = get(base_url + path)
          JSON.parse(response.body).fetch("id").sub("refs/heads/", "")
        else
          response = get(base_url + repo)
          JSON.parse(response.body).fetch("mainbranch").fetch("name")
        end
      end

      def fetch_repo_contents(repo, commit = nil, path = nil)
        raise "Commit is required if path provided!" if commit.nil? && path

        if @source.provider == "bitbucket_server"
          # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp216
          api_path = "projects/#{@source.namespace}/repos/#{repo}/browse?at=#{commit}&limit=100"
          response = get(base_url + api_path)
          JSON.parse(response.body).fetch("children").fetch("values")
        else
          api_path = "#{repo}/src"
          api_path += "/#{commit}" if commit
          api_path += "/#{path.gsub(%r{/+$}, '')}" if path
          api_path += "?pagelen=100"
          response = get(base_url + api_path)

          JSON.parse(response.body).fetch("values")
        end
      end

      def fetch_file_contents(repo, commit, path)
        if @source.provider == "bitbucket_server"
          # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp362
          path = "projects/#{@source.namespace}/repos/#{repo}/raw/#{path}?at=#{commit}"
          response = get(base_url + path)

          response.body
        else
          path = "#{repo}/src/#{commit}/#{path.gsub(%r{/+$}, '')}"
          response = get(base_url + path)

          response.body
        end
      end

      def commits(repo, branch_name = nil)
        if @source.provider == "bitbucket_server"
          # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp222
          commits_path = "projects/#{@source.namespace}/repos/#{repo}/commits?since=#{branch_name}&limit=100"
          next_page_url = base_url + commits_path
          paginate({ "next" => next_page_url })
        else
          commits_path = "#{repo}/commits/#{branch_name}?pagelen=100"
          next_page_url = base_url + commits_path
          paginate({ "next" => next_page_url })
        end
      end

      def branch(repo, branch_name)
        if @source.provider == "bitbucket_server"
          # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp209
          branch_path = "projects/#{@source.namespace}/repos/#{repo}/branches?filterText=#{branch_name}"
          response = get(base_url + branch_path)
          branch = JSON.parse(response.body)

          if branch.fetch("values").length === 0
            raise Clients::Bitbucket::NotFound.new
          end
        else
          branch_path = "#{repo}/refs/branches/#{branch_name}"
          response = get(base_url + branch_path)

          JSON.parse(response.body)
        end
      end

      def pull_requests(repo, source_branch, target_branch)
        if @source.provider == "bitbucket_server"
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
        else
          pr_path = "#{repo}/pullrequests"
          # Get pull requests with any status
          pr_path += "?status=OPEN&status=MERGED&status=DECLINED&status=SUPERSEDED"
          next_page_url = base_url + pr_path
          pull_requests = paginate({ "next" => next_page_url })

          pull_requests unless source_branch && target_branch

          pull_requests.select do |pr|
            pr_source_branch = pr.fetch("source").fetch("branch").fetch("name")
            pr_target_branch = pr.fetch("destination").fetch("branch").fetch("name")
            pr_source_branch == source_branch && pr_target_branch == target_branch
          end
        end
      end

      # rubocop:disable Metrics/ParameterLists
      def create_commit(repo, branch_name, base_commit, commit_message, files,
                        author_details)
        if @source.provider == "bitbucket_server"
          # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp218
          source_branch = self.fetch_default_branch(repo)
          source_commit_id = base_commit

          files.each do |file|
            multipart_data = multipart_form_data(
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

            source_commit_id = brand_details.fetch("id")
            source_branch = nil
          end
        else
          parameters = {
            message: commit_message, # TODO: Format markup in commit message
            author: "#{author_details.fetch(:name)} <#{author_details.fetch(:email)}>",
            parents: base_commit,
            branch: branch_name
          }

          files.each do |file|
            absolute_path = file.name.start_with?("/") ? file.name : "/" + file.name
            parameters[absolute_path] = file.content
          end

          body = encode_form_parameters(parameters)

          commit_path = "#{repo}/src"
          post(base_url + commit_path, body, "application/x-www-form-urlencoded")
        end
      end

      # rubocop:enable Metrics/ParameterLists

      # rubocop:disable Metrics/ParameterLists
      def create_pull_request(repo, pr_name, source_branch, target_branch,
                              pr_description, _labels, _work_item = nil)
        if @source.provider == "bitbucket_server"
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
        else
          content = {
            title: pr_name,
            source: {
              branch: {
                name: source_branch
              }
            },
            destination: {
              branch: {
                name: target_branch
              }
            },
            description: pr_description,
            close_source_branch: true
          }

          pr_path = "#{repo}/pullrequests"
          post(base_url + pr_path, content.to_json)
        end
      end

      # rubocop:enable Metrics/ParameterLists
      def tags(repo)
        if @source.provider == "bitbucket_server"
          # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp398
          raise "Not tested"

          path = "projects/#{@source.namespace}/repos/#{repo}/tags?limit=100"
          response = get(base_url + path)

          JSON.parse(response.body).fetch("values")
        else
          path = "#{repo}/refs/tags?pagelen=100"
          response = get(base_url + path)

          JSON.parse(response.body).fetch("values")
        end
      end

      def compare(repo, previous_tag, new_tag)
        if @source.provider == "bitbucket_server"
          raise "Not tested"

          # https://docs.atlassian.com/bitbucket-server/rest/7.14.0/bitbucket-rest.html#idp398
          path = "projects/#{@source.namespace}/repos/#{repo}/compare/changes?from=#{previous_tag}&to=#{new_tag}"
          response = get(base_url + path)

          JSON.parse(response.body).fetch("values")
        else
          path = "#{repo}/commits/?include=#{new_tag}&exclude=#{previous_tag}"
          response = get(base_url + path)

          JSON.parse(response.body).fetch("values")
        end
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

      def auth_header_for(token)
        return {} unless token

        { "Authorization" => "Bearer #{token}" }
      end

      def multipart_form_data(parameters)
        body = ""
        boundary = SecureRandom.hex(4)

        parameters.map do |key, value|
          next if value.nil?
          body = body + "--#{boundary}" + Excon::CR_NL
          body = body + "Content-Disposition: form-data; name=\"#{key}\"" + Excon::CR_NL
          body = body + "Content-Type: text/plain" + Excon::CR_NL
          body = body + Excon::CR_NL
          body = body + value + Excon::CR_NL
        end

        body = body + "--#{boundary}--" + Excon::CR_NL

        {
          "header_value" => "multipart/form-data; boundary=\"#{boundary}\"",
          "body" => body
        }
      end

      def encode_form_parameters(parameters)
        parameters.map do |key, value|
          URI.encode_www_form_component(key.to_s) + "=" + URI.encode_www_form_component(value.to_s)
        end.join("&")
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
        if @source.provider == "bitbucket_server"
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
        else
          Enumerator.new do |yielder|
            loop do
              page.fetch("values", []).each { |value| yielder << value }
              break unless page.key?("next")

              next_page_url = page.fetch("next")
              page = JSON.parse(get(next_page_url).body)
            end
          end
        end
      end

      attr_reader :auth_header
      attr_reader :credentials

      def base_url
        if @source.provider == "bitbucket_server"
          uri = URI(@source.api_endpoint)
          uri.path = uri.path + (uri.path.end_with?("/") ? '' : '/')
          uri.to_s
        else
          "https://api.bitbucket.org/2.0/repositories/"
        end
      end
    end
  end
end
