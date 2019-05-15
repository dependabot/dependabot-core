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
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == source.hostname }

        new(source, credential)
      end

      ##########
      # Client #
      ##########

      def initialize(source, credentials)
        @source = source
        @credentials = credentials
      end

      def fetch_commit(_repo, branch)
        response = get(source.api_endpoint +
          "projects/" + source.organization +
          "/repos/" + source.unscoped_repo +
          "/branches?filterText=" + branch)

        JSON.parse(response.body).fetch("values").first.fetch("latestCommit")
      end

      def fetch_default_branch(_repo)
        response = get(source.api_endpoint +
          "projects/" + source.organization +
          "/repos/" + source.unscoped_repo +
          "/branches/default")

        JSON.parse(response.body).fetch("displayId")
      end

      def fetch_repo_contents(_repo, commit = nil, path = nil)
        all_files = []
        next_page_start = 0

        loop do
          contents_url = source.api_endpoint +
                         "projects/" + source.organization +
                         "/repos/" + source.unscoped_repo +
                         "/files"
          contents_url += "/" + path unless path.nil?
          contents_url += "?at=" + commit + "&start=" + next_page_start.to_s

          parsed_response = JSON.parse(get(contents_url))

          all_files += parsed_response.fetch("values")
          next_page_start = parsed_response.fetch("nextPageStart")
          break if parsed_response.fetch("isLastPage")
        end

        unless path.nil?
          all_files = all_files.find_all { |file| (file.include? "/") == false }
        end

        all_files
      end

      def fetch_file_contents(_repo, commit, path)
        response = get(source.api_endpoint +
          "projects/" + source.organization +
          "/repos/" + source.unscoped_repo +
          "/raw/" + CGI.escape(path) + "?at=" + commit)

        response.body
      end

      def get(url)
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
    end
  end
end
