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
        credential = credentials.
                     find do |cred|
          cred["type"] == "git_source" &&
            cred["host"] == source.hostname
        end

        new(source, credential)
      end

      ##########
      # Client #
      ##########

      def initialize(source, credential)
        @source = source
        @credentials = credential
      end

      def fetch_commit(repo, branch)
        path = "#{repo}/refs/branches/#{branch}"
        response = get(base_url + path)

        JSON.parse(response.body).fetch("target").fetch("hash")
      end

      def fetch_default_branch(repo)
        response = get(base_url + repo)

        JSON.parse(response.body).fetch("mainbranch").fetch("name")
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

      def fetch_file_contents(repo, commit, path)
        path = "#{repo}/src/#{commit}/#{path.gsub(%r{/+$}, '')}"
        response = get(base_url + path)

        response.body
      end

      def tags(repo)
        path = "#{repo}/refs/tags?pagelen=100"
        response = get(base_url + path)

        JSON.parse(response.body).fetch("values")
      end

      def compare(repo, previous_tag, new_tag)
        path = "#{repo}/commits/?include=#{new_tag}&exclude=#{previous_tag}"
        response = get(base_url + path)

        JSON.parse(response.body).fetch("values")
      end

      def get(url)
        response = Excon.get(
          url,
          user: credentials&.fetch("username", nil),
          password: credentials&.fetch("password", nil),
          idempotent: true,
          **Dependabot::SharedHelpers.excon_defaults
        )
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

      def post(url, json)
        response = Excon.post(
          url,
          headers: {
            "Content-Type" => "application/json"
          },
          body: json,
          user: credentials&.fetch("username"),
          password: credentials&.fetch("password"),
          idempotent: true,
          **SharedHelpers.excon_defaults
        )
        raise NotFound if response.status == 404

        response
      end

      def branch(branch_name)
        path = "#{source.repo}/refs?"
        path += "name = \"" + branch_name + "\""

        response = get(base_url + path)

        JSON.parse(response.body).fetch("values").first
      end

      def pull_requests(source_branch, target_branch)
        path = "#{source.repo}/pullrequests?"
        path += "state=OPEN&state=MERGED&state=SUPERSEDED&state=DECLINED"
        path += "&q=source.branch.name = \"" +
        source_branch + "\" AND destination.branch.name = \"" +
        target_branch + "\""

        response = get(base_url + path)

        JSON.parse(response.body).fetch("values")
      end

      def create_commit(branch_name, _base_commit, commit_message, files,
                        author_details)
        path = "#{source.repo}/src"

        body = files.map { |file| [file.path, file.content] }
        body.push(["branch", branch_name.gsub("/", "_")])
        body.push(["message", commit_message])
        body.push(["author", author_details])

        Excon.post(
          base_url + path,
          headers: {
            "Content-Type" => "application/x-www-form-urlencoded"
          },
          body: URI.encode_www_form(body),
          user: credentials&.fetch("username"),
          password: credentials&.fetch("password"),
          idempotent: true,
          **SharedHelpers.excon_defaults
        )
      end

      def create_pull_request(pr_name, source_branch, target_branch,
      pr_description, _labels)
        content = {
          title: pr_name,
          description: pr_description,
          source: {
            branch: {
              name: source_branch.gsub("/", "_")
            }
          },
          destination: {
            branch: {
              name: target_branch
            }
          }
        }

        path = "#{source.repo}/pullrequests"

        post(base_url + path, content.to_json)
      end

      def commits(branch_name = nil)
        path = "#{source.repo}/commits"
        path += "/#{branch_name}" if branch_name

        response = get(base_url + path)

        JSON.parse(response.body).fetch("values")
      end

      private

      attr_reader :credentials
      attr_reader :source

      def base_url
        # TODO: Make this configurable when we support enterprise Bitbucket
        "https://api.bitbucket.org/2.0/repositories/"
      end
    end
  end
end
