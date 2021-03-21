# frozen_string_literal: true

require "dependabot/pull_request_creator/labeler"

module Dependabot
  class PullRequestCreator
    module Labelers
      class Gitlab < Labeler
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
          @client.labels(source.repo, per_page: 100).auto_paginate.map(&:name)
        end

        def create_label(label, colour, description)
          @client.create_label(
            source.repo,
            label,
            '#' + colour,
            description: description
          )
          @labels = [*@labels, label].uniq
        end
      end
    end
  end
end
