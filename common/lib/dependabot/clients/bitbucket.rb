# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module Clients
    class Bitbucket
      extend T::Sig

      class NotFound < StandardError; end

      class Unauthorized < StandardError; end

      class Forbidden < StandardError; end

      class TimedOut < StandardError; end

      #######################
      # Constructor methods #
      #######################

      sig do
        params(
          source: Dependabot::Source,
          credentials: T::Array[Dependabot::Credential]
        )
          .returns(Dependabot::Clients::Bitbucket)
      end
      def self.for_source(source:, credentials:)
        credential =
          credentials
          .select { |cred| cred["type"] == "git_source" }
          .find { |cred| cred["host"] == source.hostname }

        new(credentials: credential)
      end

      ##########
      # Client #
      ##########

      sig { params(credentials: T.nilable(Dependabot::Credential)).void }
      def initialize(credentials:)
        @credentials = credentials
        @auth_header = T.let(auth_header_for(credentials&.fetch("token", nil)), T::Hash[String, String])
      end

      sig { params(repo: String, branch: String).returns(String) }
      def fetch_commit(repo, branch)
        path = "#{repo}/refs/branches/#{branch}"
        response = get(base_url + path)

        JSON.parse(response.body).fetch("target").fetch("hash")
      end

      sig { params(repo: String).returns(String) }
      def fetch_default_branch(repo)
        response = get(base_url + repo)

        JSON.parse(response.body).fetch("mainbranch").fetch("name")
      end

      sig do
        params(
          repo: String,
          commit: T.nilable(String),
          path: T.nilable(String)
        )
          .returns(T::Array[T::Hash[String, T.untyped]])
      end
      def fetch_repo_contents(repo, commit = nil, path = nil)
        raise "Commit is required if path provided!" if commit.nil? && path

        api_path = "#{repo}/src"
        api_path += "/#{commit}" if commit
        api_path += "/#{path.gsub(%r{/+$}, '')}" if path
        api_path += "?pagelen=100"
        response = get(base_url + api_path)

        JSON.parse(response.body).fetch("values")
      end

      sig do
        params(
          repo: String,
          commit: String,
          path: String
        )
          .returns(String)
      end
      def fetch_file_contents(repo, commit, path)
        path = "#{repo}/src/#{commit}/#{path.gsub(%r{/+$}, '')}"
        response = get(base_url + path)

        response.body
      end

      sig do
        params(
          repo: String,
          branch_name: T.nilable(String)
        )
          .returns(T::Enumerator[T::Hash[String, T.untyped]])
      end
      def commits(repo, branch_name = nil)
        commits_path = "#{repo}/commits/#{branch_name}?pagelen=100"
        next_page_url = base_url + commits_path
        paginate({ "next" => next_page_url })
      end

      sig do
        params(
          repo: String,
          branch_name: String
        )
          .returns(T::Hash[String, T.untyped])
      end
      def branch(repo, branch_name)
        branch_path = "#{repo}/refs/branches/#{branch_name}"
        response = get(base_url + branch_path)

        JSON.parse(response.body)
      end

      sig do
        params(
          repo: String,
          source_branch: T.nilable(String),
          target_branch: T.nilable(String),
          status: T::Array[String]
        )
          .returns(T::Array[T::Hash[String, T.untyped]])
      end
      def pull_requests(repo, source_branch, target_branch, status = %w(OPEN MERGED DECLINED SUPERSEDED))
        pr_path = "#{repo}/pullrequests?"
        # Get pull requests with given status
        status.each { |n| pr_path += "status=#{n}&" }
        next_page_url = base_url + pr_path
        pull_requests = paginate({ "next" => next_page_url })

        pull_requests unless source_branch && target_branch

        pull_requests.select do |pr|
          if source_branch.nil?
            source_branch_matches = true
          else
            pr_source_branch = pr.fetch("source").fetch("branch").fetch("name")
            source_branch_matches = pr_source_branch == source_branch
          end
          pr_target_branch = pr.fetch("destination").fetch("branch").fetch("name")
          source_branch_matches && pr_target_branch == target_branch
        end
      end

      # rubocop:disable Metrics/ParameterLists
      sig do
        params(
          repo: String,
          branch_name: String,
          base_commit: String,
          commit_message: String,
          files: T::Array[Dependabot::DependencyFile],
          author_details: T::Hash[Symbol, String]
        )
          .void
      end
      def create_commit(repo, branch_name, base_commit, commit_message, files,
                        author_details)
        parameters = {
          message: commit_message, # TODO: Format markup in commit message
          author: "#{author_details.fetch(:name)} <#{author_details.fetch(:email)}>",
          parents: base_commit,
          branch: branch_name
        }

        files.each do |file|
          parameters[file.path] = file.content
        end

        body = encode_form_parameters(parameters)

        commit_path = "#{repo}/src"
        post(base_url + commit_path, body, "application/x-www-form-urlencoded")
      end
      # rubocop:enable Metrics/ParameterLists

      # rubocop:disable Metrics/ParameterLists
      sig do
        params(
          repo: String,
          pr_name: String,
          source_branch: String,
          target_branch: String,
          pr_description: String,
          _labels: T.nilable(T::Array[String]),
          _work_item: T.nilable(Integer)
        )
          .void
      end
      def create_pull_request(repo, pr_name, source_branch, target_branch,
                              pr_description, _labels, _work_item = nil)
        reviewers = default_reviewers(repo)

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
          reviewers: reviewers,
          close_source_branch: true
        }

        pr_path = "#{repo}/pullrequests"
        post(base_url + pr_path, content.to_json)
      end
      # rubocop:enable Metrics/ParameterLists

      sig { params(repo: String, pr_id: Integer, comment: T.nilable(String)).void }
      def decline_pull_request(repo, pr_id, comment = nil)
        # https://developer.atlassian.com/cloud/bitbucket/rest/api-group-pullrequests/
        decline_path = "#{repo}/pullrequests/#{pr_id}/decline"
        post(base_url + decline_path, "")

        comment = "Dependabot declined the pull request." if comment.nil?

        content = {
          content: {
            raw: comment
          }
        }

        comment_path = "#{repo}/pullrequests/#{pr_id}/comments"
        post(base_url + comment_path, content.to_json)
      end

      sig { returns(T.nilable(String)) }
      def current_user
        base_url = "https://api.bitbucket.org/2.0/user?fields=uuid"
        response = get(base_url)
        JSON.parse(response.body).fetch("uuid")
      rescue Unauthorized
        nil
      end

      sig { params(repo: String).returns(T::Array[T::Hash[String, String]]) }
      def default_reviewers(repo)
        current_uuid = current_user
        path = "#{repo}/default-reviewers?pagelen=100&fields=values.uuid,next"
        reviewers_url = base_url + path

        default_reviewers = paginate({ "next" => reviewers_url })

        reviewer_data = []

        default_reviewers.each do |reviewer|
          reviewer_data.append({ uuid: reviewer.fetch("uuid") }) unless current_uuid == reviewer.fetch("uuid")
        end

        reviewer_data
      end

      sig { params(repo: String).returns(T::Array[T::Hash[String, String]]) }
      def tags(repo)
        path = "#{repo}/refs/tags?pagelen=100"
        response = get(base_url + path)

        JSON.parse(response.body).fetch("values")
      end

      sig do
        params(
          repo: String,
          previous_tag: String,
          new_tag: String
        )
          .returns(T::Array[T::Hash[String, T.untyped]])
      end
      def compare(repo, previous_tag, new_tag)
        path = "#{repo}/commits/?include=#{new_tag}&exclude=#{previous_tag}"
        response = get(base_url + path)

        JSON.parse(response.body).fetch("values")
      end

      sig { params(url: String).returns(Excon::Response) }
      def get(url)
        response = Excon.get(
          URI::DEFAULT_PARSER.escape(url),
          user: credentials&.fetch("username", nil),
          password: credentials&.fetch("password", nil),
          # Setting to false to prevent Excon retries, use BitbucketWithRetries for retries.
          idempotent: false,
          **Dependabot::SharedHelpers.excon_defaults(
            headers: auth_header
          )
        )
        raise Unauthorized if response.status == 401
        raise Forbidden if response.status == 403
        raise NotFound if response.status == 404

        if response.status >= 400
          raise "Unhandled Bitbucket error!\n" \
                "Status: #{response.status}\n" \
                "Body: #{response.body}"
        end

        response
      end

      sig do
        params(
          url: String,
          body: String,
          content_type: String
        )
          .returns(Excon::Response)
      end
      def post(url, body, content_type = "application/json")
        headers = auth_header

        headers = if body.empty?
                    headers.merge({ "Accept" => "application/json" })
                  else
                    headers.merge({ "Content-Type" => content_type })
                  end

        response = Excon.post(
          url,
          body: body,
          user: credentials&.fetch("username", nil),
          password: credentials&.fetch("password", nil),
          idempotent: false,
          **SharedHelpers.excon_defaults(
            headers: headers
          )
        )
        raise Unauthorized if response.status == 401
        raise Forbidden if response.status == 403
        raise NotFound if response.status == 404
        raise TimedOut if response.status == 555

        response
      end

      private

      sig { params(token: T.nilable(String)).returns(T::Hash[String, String]) }
      def auth_header_for(token)
        return {} unless token

        { "Authorization" => "Bearer #{token}" }
      end

      sig { params(parameters: T::Hash[String, String]).returns(String) }
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
      #     first_page = JSON.parse(response.body)
      #     paginate(first_page)
      sig do
        type_parameters(:T)
          .params(page: T.all(T.type_parameter(:T), T::Hash[String, T.untyped]))
          .returns(T::Enumerator[T.type_parameter(:T)])
      end
      def paginate(page)
        Enumerator.new do |yielder|
          loop do
            page.fetch("values", []).each { |value| yielder << value }
            break unless page.key?("next")

            next_page_url = page.fetch("next")
            page = T.cast(JSON.parse(get(next_page_url).body), T.all(T::Hash[String, T.untyped], T.type_parameter(:T)))
          end
        end
      end

      sig { returns(T::Hash[String, String]) }
      attr_reader :auth_header

      sig { returns(T.nilable(Dependabot::Credential)) }
      attr_reader :credentials

      sig { returns(String) }
      def base_url
        # TODO: Make this configurable when we support enterprise Bitbucket
        "https://api.bitbucket.org/2.0/repositories/"
      end
    end
  end
end
