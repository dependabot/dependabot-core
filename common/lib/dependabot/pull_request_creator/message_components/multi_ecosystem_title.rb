# typed: strict
# frozen_string_literal: true

require "dependabot/pull_request_creator/message_components/pr_title"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Builds PR title for multi-ecosystem grouped updates
      # This is intended for use by dependabot-api to ensure consistent formatting
      class MultiEcosystemTitle < PrTitle
        extend T::Sig

        sig { override.returns(String) }
        def base_title
          updates = dependencies.map(&:name).uniq.count
          group_name = dependency_group ? T.must(dependency_group).name : "dependencies"

          if dependencies.one?
            dependency = dependencies.first
            "bump #{T.must(dependency).display_name} in the #{group_name} group across multiple ecosystems"
          else
            "bump the #{group_name} group with #{updates} update#{'s' if updates > 1} across multiple ecosystems"
          end
        end
      end
    end
  end
end
