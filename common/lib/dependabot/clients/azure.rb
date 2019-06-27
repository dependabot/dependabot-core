# frozen_string_literal: true

require "dependabot/shared_helpers"
require "excon"

module Dependabot
  module Clients
    class Azure
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
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/stats/branches?name=" + branch)

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

        unless branch_name.to_s.empty?
          commits_url += "?searchCriteria.itemVersion.version=" + branch_name
        end

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

      def create_commit(branch_name, base_commit, commit_message, files)
        content = {
          refUpdates: [
            { name: "refs/heads/" + branch_name, oldObjectId: base_commit }
          ],
          commits: [
            {
              comment: commit_message,
              changes: files.map do |file|
                {
                  changeType: "edit",
                  item: { path: file.path },
                  newContent: {
                    content: Base64.encode64(file.content),
                    contentType: "base64encoded"
                  }
                }
              end
            }
          ]
        }

        post(source.api_endpoint + source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/pushes?api-version=5.0", content.to_json)
      end

      def create_pull_request(pr_name, source_branch, target_branch,
                              pr_description, labels)
        # Azure DevOps only support descriptions up to 4000 characters (https://developercommunity.visualstudio.com/content/problem/608770/remove-4000-character-limit-on-pull-request-descri.html)
        azure_max_length = 3999
        if pr_description.length > azure_max_length
          truncated_msg = "...\n\n_Description has been truncated_"
          truncate_length = azure_max_length - truncated_msg.length
          pr_description = pr_description[0..truncate_length] + truncated_msg
        end

        content = {
          sourceRefName: "refs/heads/" + source_branch,
          targetRefName: "refs/heads/" + target_branch,
          title: pr_name,
          description: pr_description,
          labels: labels.map { |label| { name: label } }
        }

        post(source.api_endpoint +
          source.organization + "/" + source.project +
          "/_apis/git/repositories/" + source.unscoped_repo +
          "/pullrequests?api-version=5.0", content.to_json)
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

      private

      attr_reader :credentials
      attr_reader :source
    end
  end
end
