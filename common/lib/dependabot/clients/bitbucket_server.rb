# frozen_string_literal: true

require "dependabot/shared_helpers"
require "faraday"
require "faraday_middleware"

module Dependabot
  module Clients
    class BitbucketServer
      class NotFound < StandardError; end
      class Unauthorized < StandardError; end
      class Forbidden < StandardError; end

      ##########
      # Client #
      ##########

      def self.for_source(source:, credentials:)
        credential = credentials.
                     find do |cred|
          cred["type"] == "git_source" &&
            cred["host"] == source.hostname
        end

        new(source, credential)
      end

      def initialize(source, credential)
        @source = source
        @credentials = credential
      end

      def fetch_commit(_repo_name, branch)
        path = "commits?limit=1&start=0&until=#{branch}"
        response = get(File.join(repo_path, path))

        response.body.dig("values", 0, "id")
      end

      def fetch_commit_message(branch)
        path = "commits?limit=1&start=0&until=#{branch}"
        response = get(File.join(repo_path, path))

        response.body.dig("values", 0, "message")
      end

      def fetch_recent_commits(branch = nil)
        path = "commits?limit=100&start=0"
        path += "&until=#{branch}" if branch
        response = get(File.join(repo_path, path))

        response.body.dig("values")
      end

      def create_commit(branch_name, message, files)
        files.each do |file|
          content = Faraday::UploadIO.new(
            StringIO.new(file.content), "application/text", file.path
          )
          body = {
            content: content,
            branch: branch_name,
            message: message,
            sourceCommitId: fetch_file_commit(branch_name, file.path)
          }
          url = File.join(repo_path, "browse", file.path)
          put_multipart(url, body)
        end
      end

      def fetch_file_commit(branch_name, file_path)
        file_path = file_path.start_with?("/") ? file_path[1..-1] : file_path
        path = "commits?limit=1&start=0&until=#{branch_name}&path=#{file_path}"
        url = File.join(repo_path, path)

        response = get(url)
        response.body.dig("values", 0, "id")
      end

      def fetch_default_branch(_repo_name)
        url = File.join(repo_path, "/branches/default")
        response = get(url)

        response.body.fetch("displayId")
      end

      def fetch_branch_by_name(branch)
        url = File.join(repo_path, "/branches?filterText=#{branch}")
        response = get(url)

        response.body.dig("values")&.
          find { |b| b["displayId"] == branch }&.
          dig("id")
      end

      def create_branch(branch_name, base_commit)
        url = File.join(repo_path, "/branches")
        body = {
          name: branch_name,
          startPoint: base_commit
        }

        post(url, body)
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def fetch_repo_contents(_repo_name, commit = nil, path = nil)
        raise "Commit is required if path provided!" if commit.nil? && path

        api_path = "browse"
        api_path += "/#{path.gsub(%r{/+$}, '')}" if path
        api_path += "?at=#{commit}&" if commit
        api_path += path || commit ? "limit=100" : "?limit=100"
        response = get(File.join(repo_path, api_path))

        response.body.dig("children", "values")&.map do |file|
          file["path"] = if path.nil? || path.empty?
                           file.dig("path", "name")
                         else
                           path
                         end
          file
        end
      end

      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def fetch_file_contents(_repo_name, commit, path)
        path = "raw/#{path.gsub(%r{/+$}, '')}?at=#{commit}"
        response = get(File.join(repo_path, path))
        response.body
      end

      def tags(_repo_name)
        url = File.join(repo_path, "tags?limit=100")
        response = get(url)

        response.body.fetch("values")
      end

      def compare(_repo_name, previous_tag, new_tag)
        path = "compare/commits?to=#{new_tag}&from=#{previous_tag}"
        response = get(File.join(repo_path, path))

        response.body.fetch("values")
      end

      def fetch_pull_request_for_branch(branch)
        path = "/pull-requests?at=refs/heads/#{branch}&direction=outgoing"
        url = File.join(repo_path, path)
        response = get(url)

        response.body.dig("values", 0)
      end

      def create_pull_request(title, from, to, description, reviewers = nil)
        url = File.join(repo_path, "pull-requests")
        from_ref = { "id" => from }
        to_ref   = { "id" => to }
        body = {
          title: title,
          description: description,
          state: "OPEN",
          fromRef: from_ref,
          toRef: to_ref,
          reviewers: Array(reviewers).map { |r| { user: { name: r } } }
        }.to_json
        post(url, body)
      end

      private

      attr_reader :credentials
      attr_reader :source

      def request(method, url, body = nil)
        res = conn.public_send(method) do |req|
          req.url url
          req.headers["Content-Type"] = "application/json"
          req.body = body unless body.nil?
        end

        handle_response(res)
      end

      def handle_response(response)
        raise Unauthorized if response.status == 401
        raise Forbidden if response.status == 403
        raise NotFound if response.status == 404

        if response.status >= 400
          raise "Unhandled Bitbucket error!\n"\
                "Status: #{response.status}\n"\
                "Body: #{response.body}"
        end

        response
      end

      %i(get post).each do |method|
        define_method(method.to_s) do |*args|
          request(method, *args)
        end
      end

      def put_multipart(url, body)
        conn.put do |req|
          req.url url
          req.body = body
          req.headers["Content-Type"] = "multipart/form-data"
        end
      end

      def conn
        @conn = ::Faraday.new do |faraday|
          faraday.basic_auth(username, password)
          faraday.request :json
          faraday.request :multipart
          faraday.response :json, content_type: /\bjson$/
          faraday.adapter Faraday.default_adapter
        end
      end

      def username
        credentials&.dig("username")
      end

      def password
        credentials&.dig("password")
      end

      def repo_path
        File.join(source.api_endpoint, source.repo)
      end
    end
  end
end
