# frozen_string_literal: true

require "gitlab"
require "octokit"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class Labeler
      DEPENDENCIES_LABEL_REGEX = %r{^dependenc[^/]+$}i

      def initialize(source:, custom_labels:, credentials:,
                     includes_security_fixes:)
        @source                  = source
        @custom_labels           = custom_labels
        @credentials             = credentials
        @includes_security_fixes = includes_security_fixes
      end

      def create_default_labels_if_required
        create_default_dependencies_label_if_required
        create_default_security_label_if_required
      end

      def labels_for_pr
        return default_labels_for_pr unless includes_security_fixes?

        [
          *default_labels_for_pr,
          labels.find { |l| l.match?(/security/i) }
        ].uniq
      end

      def label_pull_request(pull_request_number)
        create_default_labels_if_required

        return if labels_for_pr.none?
        raise "Only GitHub!" unless source.provider == "github"

        github_client_for_source.add_labels_to_an_issue(
          source.repo,
          pull_request_number,
          labels_for_pr
        )
      end

      private

      attr_reader :source, :custom_labels, :credentials

      def includes_security_fixes?
        @includes_security_fixes
      end

      def create_default_dependencies_label_if_required
        return if custom_labels
        return if dependencies_label_exists?

        create_dependencies_label
      end

      def create_default_security_label_if_required
        return unless includes_security_fixes?
        return if security_label_exists?

        create_security_label
      end

      def default_labels_for_pr
        if custom_labels then custom_labels & labels
        else [labels.find { |l| l.match?(DEPENDENCIES_LABEL_REGEX) }]
        end
      end

      def dependencies_label_exists?
        labels.any? { |l| l.match?(DEPENDENCIES_LABEL_REGEX) }
      end

      def security_label_exists?
        labels.any? { |l| l.match?(/security/i) }
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

      def create_dependencies_label
        case source.provider
        when "github" then create_github_dependencies_label
        when "gitlab" then create_gitlab_dependencies_label
        else raise "Unsupported provider #{source.provider}"
        end
      end

      def create_security_label
        case source.provider
        when "github" then create_github_security_label
        when "gitlab" then create_gitlab_security_label
        else raise "Unsupported provider #{source.provider}"
        end
      end

      def create_github_dependencies_label
        github_client_for_source.add_label(
          source.repo, "dependencies", "0025ff",
          description: "Pull requests that update a dependency file"
        )
        @labels = [*@labels, "dependencies"].uniq
      rescue Octokit::UnprocessableEntity => error
        raise unless error.errors.first.fetch(:code) == "already_exists"
        @labels = [*@labels, "dependencies"].uniq
      end

      def create_gitlab_dependencies_label
        gitlab_client_for_source.create_label(
          source.repo, "dependencies", "#0025ff",
          description: "Pull requests that update a dependency file"
        )
        @labels = [*@labels, "dependencies"].uniq
      end

      def create_github_security_label
        github_client_for_source.add_label(
          source.repo, "security", "ee0701",
          description: "Pull requests that address a security vulnerability"
        )
        @labels = [*@labels, "security"].uniq
      rescue Octokit::UnprocessableEntity => error
        raise unless error.errors.first.fetch(:code) == "already_exists"
        @labels = [*@labels, "security"].uniq
      end

      def create_gitlab_security_label
        gitlab_client_for_source.create_label(
          source.repo, "security", "#ee0701",
          description: "Pull requests that address a security vulnerability"
        )
        @labels = [*@labels, "security"].uniq
      end

      def github_client_for_source
        @github_client_for_source ||=
          Dependabot::GithubClientWithRetries.for_source(
            source: source,
            credentials: credentials
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
