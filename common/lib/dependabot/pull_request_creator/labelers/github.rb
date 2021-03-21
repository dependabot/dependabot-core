# frozen_string_literal: true

require "octokit"
require "dependabot/pull_request_creator/labeler"

module Dependabot
  class PullRequestCreator
    module Labelers
      class Github < Labeler
        @package_manager_labels = {}

        def initialize(source:, custom_labels:, dependencies:,
                       includes_security_fixes:, label_language:,
                       automerge_candidate:, client:)
          super(
            source: source,
            custom_labels: custom_labels,
            includes_security_fixes: includes_security_fixes,
            dependencies: dependencies,
            label_language: label_language,
            automerge_candidate: automerge_candidate
          )
          @client = client
        end

        def labels
          @labels ||= fetch_labels
        end

        def label_pull_request(pull_request_number)
          create_default_labels_if_required

          return if labels_for_pr.none?

          @client.add_labels_to_an_issue(
            source.repo,
            pull_request_number,
            labels_for_pr
          )
        rescue Octokit::UnprocessableEntity, Octokit::NotFound
          retry_count ||= 0
          retry_count += 1
          raise if retry_count > 10

          sleep(rand(1..1.99))
          retry
        end

        def create_dependencies_label
          create_label(
            DEFAULT_DEPENDENCIES_LABEL,
            "0366d6",
            "Pull requests that update a dependency file"
          )
        end

        def create_security_label
          create_label(
            DEFAULT_SECURITY_LABEL,
            "ee0701",
            "Pull requests that address a security vulnerability"
          )
        end

        def create_language_label
          create_label(
            language_name,
            colour,
            "Pull requests that update #{language_name.capitalize} code"
          )
        end

        private

        def fetch_labels
          labels ||= @client.labels(source.repo, per_page: 100).map(&:name)

          next_link = @client.last_response.rels[:next]

          while next_link
            next_page = next_link.get
            labels += next_page.data.map(&:name)
            next_link = next_page.rels[:next]
          end

          labels
        end

        def create_label(label, colour, description)
          @client.add_label(
            source.repo,
            label,
            colour,
            description: description,
            accept: "application/vnd.github.symmetra-preview+json"
          )
          @labels = [*@labels, label].uniq
        rescue Octokit::UnprocessableEntity => e
          raise unless e.errors.first.fetch(:code) == "already_exists"

          @labels = [*@labels, label].uniq
        end
      end
    end
  end
end
