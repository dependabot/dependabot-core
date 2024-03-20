# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    # Message is a static alternative to MessageBuilder
    class Message
      extend T::Sig

      sig { returns(T.nilable(String)) }
      attr_reader :commit_message

      sig { returns(T.nilable(String)) }
      attr_reader :pr_name

      sig { returns(T.nilable(String)) }
      attr_reader :pr_message

      sig do
        params(
          commit_message: T.nilable(String),
          pr_name: T.nilable(String),
          pr_message: T.nilable(String)
        )
          .void
      end
      def initialize(commit_message: nil, pr_name: nil, pr_message: nil)
        @commit_message = commit_message
        @pr_name = pr_name
        @pr_message = pr_message
      end
    end
  end
end
