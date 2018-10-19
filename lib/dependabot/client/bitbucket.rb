# frozen_string_literal: true

require "dependabot/shared_helpers"
require "excon"

module Dependabot
  module Client
    class BitbucketNotFound < StandardError; end
    class BitBucket
      def initialize(credentials)
        @credentials = credentials
      end

      def fetch_commit(repo, branch)
        path = "#{repo}/refs/branches/#{branch}"
        response = api_call(path)

        JSON.parse(response.body).fetch("target").fetch("hash")
      end

      def fetch_default_branch(repo)
        response = api_call(repo)

        JSON.parse(response.body).fetch("mainbranch").fetch("name")
      end

      def fetch_repo_contents(repo, commit, path)
        path = "#{repo}/src/#{commit}/#{path.gsub(%r{/+$}, '')}?pagelen=100"
        response = api_call(path)

        JSON.parse(response.body).fetch("values")
      end

      def fetch_file_contents(repo, commit, path)
        path = "#{repo}/src/#{commit}/#{path.gsub(%r{/+$}, '')}"
        api_call(path)
      end

      private

      def api_call(path)
        response = Excon.get(
          "https://api.bitbucket.org/2.0/repositories/" + path,
          user: @credentials&.fetch("username"),
          password: @credentials&.fetch("password"),
          idempotent: true,
          **SharedHelpers.excon_defaults
        )
        raise BitbucketNotFound if response.status >= 300

        response
      end
    end
  end
end
