# frozen_string_literal: true

require "gitlab"
require "octokit"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class Labeler
      def initialize(source:, custom_labels:, credentials:,
                     includes_security_fixes:)
        @source                  = source
        @custom_labels           = custom_labels
        @credentials             = credentials
        @includes_security_fixes = includes_security_fixes
      end

      def create_default_label_if_required
        return if custom_labels
        return if dependencies_label_exists?

        create_label
      end

      def labels_for_pr
        if custom_labels then custom_labels & labels
        else [labels.find { |l| l.match?(/dependenc/i) }]
        end
      end

      def label_pull_request(pull_request_number)
        create_default_label_if_required

        return if labels_for_pr.none?
        raise "Only GitHub!" unless source.provider == "github"

        github_client_for_source.add_labels_to_an_issue(
          source.repo,
          pull_request_number,
          labels_for_pr
        )
      end

      private

      attr_reader :source, :custom_labels, :includes_security_fixes,
                  :credentials

      def dependencies_label_exists?
        labels.any? { |l| l.match?(/dependenc/i) }
      end

      def labels
        @labels ||=
          case source.provider
          when "github" then fetch_github_labels
          when "gitlab" then fetch_gitlab_labels
          else raise "Unsupported provider #{source.provider}"
          end
      end

      def fetch_github_labels
        github_client_for_source.
          labels(source.repo, per_page: 100).
          map(&:name)
      end

      def fetch_gitlab_labels
        gitlab_client_for_source.
          labels(source.repo).
          map(&:name)
      end

      def create_label
        case source.provider
        when "github" then create_github_label
        when "gitlab" then create_gitlab_label
        else raise "Unsupported provider #{source.provider}"
        end
      end

      def create_github_label
        github_client_for_source.add_label(
          source.repo, "dependencies", "0025ff",
          description: "Pull requests that update a dependency file"
        )
        @labels = [*@labels, "dependencies"].uniq
      rescue Octokit::UnprocessableEntity => error
        raise unless error.errors.first.fetch(:code) == "already_exists"
        @labels = [*@labels, "dependencies"].uniq
      end

      def create_gitlab_label
        gitlab_client_for_source.create_label(
          source.repo, "dependencies", "#0025ff",
          description: "Pull requests that update a dependency file"
        )
        @labels = [*@labels, "dependencies"].uniq
      end

      def github_client_for_source
        access_token =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == source.hostname }.
          fetch("password")

        @github_client_for_source ||=
          Dependabot::GithubClientWithRetries.new(
            access_token: access_token,
            api_endpoint: source.api_endpoint
          )
      end

      def gitlab_client_for_source
        access_token =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == source.hostname }&.
          fetch("password")

        @gitlab_client_for_source ||=
          ::Gitlab.client(
            endpoint: "https://gitlab.com/api/v4",
            private_token: access_token || ""
          )
      end
    end
  end
end
