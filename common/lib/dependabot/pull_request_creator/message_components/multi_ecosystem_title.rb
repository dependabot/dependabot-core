# typed: strong
# frozen_string_literal: true

require "dependabot/pull_request_creator/message_components/pr_title"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Generates PR titles for multi-ecosystem updates
      # This is for future use by dependabot-api
      class MultiEcosystemTitle < PrTitle
        extend T::Sig

        private

        sig { returns(String) }
        def base_title
          group_name = options[:group_name] || "dependencies"
          update_count = dependencies.map(&:name).uniq.count

          "bump the \"#{group_name}\" group with #{update_count} update#{'s' if update_count > 1} " \
            "across multiple ecosystems"
        end
      end
    end
  end
end
