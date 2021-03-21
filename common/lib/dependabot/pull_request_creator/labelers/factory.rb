# frozen_string_literal: true

module Dependabot
  class PullRequestCreator
    module Labelers
      class Factory
        class << self
          def for_source(source:, custom_labels:, credentials:, includes_security_fixes:, dependencies:,
                         label_language:, automerge_candidate:)
            labeler_params = {
              custom_labels: custom_labels,
              includes_security_fixes: includes_security_fixes,
              dependencies: dependencies,
              label_language: label_language,
              automerge_candidate: automerge_candidate
            }

            case source.provider
            when "github" then github_labeler(source, credentials, labeler_params)
            when "gitlab" then gitlab_labeler(source, credentials, labeler_params)
            when "azure" then azure_labeler(source, labeler_params)
            when "bitbucket" then base_labeler(source, labeler_params)
            when "codecommit" then base_labeler(source, labeler_params)
            else raise "Unsupported provider '#{source.provider}'."
            end
          end

          private

          def github_labeler(source, credentials, labeler_params)
            require "dependabot/pull_request_creator/labelers/github"
            require "dependabot/clients/github_with_retries"
            client = Dependabot::Clients::GithubWithRetries.for_source(
              source: source,
              credentials: credentials
            )
            Dependabot::PullRequestCreator::Labelers::Github.new(
              source: source,
              client: client,
              **labeler_params
            )
          end

          def gitlab_labeler(source, credentials, labeler_params)
            require "dependabot/pull_request_creator/labelers/gitlab"
            require "dependabot/clients/gitlab_with_retries"
            client = Dependabot::Clients::GitlabWithRetries.for_source(
              source: source,
              credentials: credentials
            )
            Dependabot::PullRequestCreator::Labelers::Gitlab.new(
              source: source,
              client: client,
              **labeler_params
            )
          end

          def azure_labeler(source, labeler_params)
            require "dependabot/pull_request_creator/labelers/azure"
            Dependabot::PullRequestCreator::Labelers::Azure.new(
              source: source,
              **labeler_params
            )
          end

          def base_labeler(source, labeler_params)
            require "dependabot/pull_request_creator/labeler"
            Dependabot::PullRequestCreator.Labeler.new(
              source: source,
              **labeler_params
            )
          end
        end
      end
    end
  end
end
