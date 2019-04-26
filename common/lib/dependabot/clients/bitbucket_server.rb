# frozen_string_literal: true

require "dependabot/shared_helpers"
require "excon"

module Dependabot
  module Clients
    class BitbucketServer
      class NotFound < StandardError; end

      #######################
      # Constructor methods #
      #######################

      def self.for_source(source:, credentials:)
        credential =
          credentials.
          find { |cred| cred["type"] == "git_source" && cred["host"] == source.hostname }

        new(source, credential)
      end

      ##########
      # Client #
      ##########

      def initialize(source, credentials)
        @source = source
        @credentials = credentials
      end

      def fetch_commit(repo, branch)
        response = get(source.api_endpoint + "projects/" + source.organization + "/repos/" + source.unscoped_repo + "/branches/default")

        JSON.parse(response.body).fetch("latestCommit")
      end

      def fetch_default_branch(repo)
        response = get(source.api_endpoint + "projects/" + source.organization + "/repos/" + source.unscoped_repo + "/branches/default")

        JSON.parse(response.body).fetch("id")
      end

      def fetch_repo_contents(repo, commit = nil, path = nil)
        all_files = []
        next_page_start = 0

        loop do
            if path != nil then
              response = get(source.api_endpoint + "projects/" + source.organization + "/repos/" + source.unscoped_repo + "/files/" + path + "?at=" + commit + "&start=" + next_page_start.to_s)
            else
              response = get(source.api_endpoint + "projects/" + source.organization + "/repos/" + source.unscoped_repo + "/files?at=" + commit + "&start=" + next_page_start.to_s)
            end
            parsed_response = JSON.parse(response.body)

            all_files = all_files + parsed_response.fetch("values")
            next_page_start = parsed_response.fetch("nextPageStart")
            break if parsed_response.fetch("isLastPage")
        end

        if path != nil then
          all_files = all_files.find_all {|file| (file.include? ?/) == false}
        end

        all_files
      end

      def fetch_file_contents(repo, commit, path)
        response = get(source.api_endpoint + "projects/" + source.organization + "/repos/" + source.unscoped_repo + "/raw/" + URI.encode(path) + "?at=" + commit)

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
        a = credentials&.fetch("username")
        response = Excon.get(
          url,
          user: credentials&.fetch("username"),
          password: credentials&.fetch("password"),
          idempotent: true,
          **SharedHelpers.excon_defaults
        )
        raise NotFound if response.status == 404

        response
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
