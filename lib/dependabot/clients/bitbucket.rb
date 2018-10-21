# frozen_string_literal: true

require "dependabot/shared_helpers"
require "excon"

module Dependabot
  module Clients
    class Bitbucket
      class NotFound < StandardError; end

      #######################
      # Constructor methods #
      #######################

      def self.for_bitbucket_dot_org(credentials:)
        credential =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == "bitbucket.org" }

        new(credential)
      end

      ##########
      # Client #
      ##########

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

      def fetch_repo_contents(repo, commit = nil, path = nil)
        raise "Commit is required if path provided!" if commit.nil? && path

        api_path = "#{repo}/src"
        api_path += "/#{commit}" if commit
        api_path += "/#{path.gsub(%r{/+$}, '')}" if path
        api_path += "?pagelen=100"
        response = api_call(api_path)

        JSON.parse(response.body).fetch("values")
      end

      def fetch_file_contents(repo, commit, path)
        path = "#{repo}/src/#{commit}/#{path.gsub(%r{/+$}, '')}"
        response = api_call(path)

        response.body
      end

      def tags(repo)
        path = "#{repo}/refs/tags?pagelen=100"
        response = api_call(path)

        JSON.parse(response.body).fetch("values")
      end

      def compare(repo, previous_tag, new_tag)
        path = "#{repo}/commits/?include=#{new_tag}&exclude=#{previous_tag}"
        response = api_call(path)

        JSON.parse(response.body).fetch("values")
      end

      private

      attr_reader :credentials

      def api_call(path)
        response = Excon.get(
          "https://api.bitbucket.org/2.0/repositories/" + path,
          user: credentials&.fetch("username"),
          password: credentials&.fetch("password"),
          idempotent: true,
          **SharedHelpers.excon_defaults
        )
        raise NotFound if response.status >= 300

        response
      end
    end
  end
end
