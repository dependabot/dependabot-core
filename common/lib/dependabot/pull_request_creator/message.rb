# frozen_string_literal: true

module Dependabot
  class PullRequestCreator
    # Message is a static alternative to MessageBuilder
    class Message
      attr_reader :commit_message, :pr_name, :pr_message

      def initialize(commit_message: nil, pr_name: nil, pr_message: nil)
        @commit_message = commit_message
        @pr_name = pr_name
        @pr_message = pr_message
      end
    end
  end
end
