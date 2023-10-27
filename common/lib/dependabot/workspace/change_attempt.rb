# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Workspace
    class ChangeAttempt
      extend T::Sig

      sig { returns(T.nilable(String)) }
      attr_reader :diff

      sig { returns(T.nilable(StandardError)) }
      attr_reader :error

      sig { returns(String) }
      attr_reader :id

      sig { returns(T.nilable(String)) }
      attr_reader :memo

      sig { returns(Dependabot::Workspace::Base) }
      attr_reader :workspace

      sig do
        params(
          workspace: Dependabot::Workspace::Base,
          id: String,
          memo: T.nilable(String),
          diff: T.nilable(String),
          error: T.nilable(StandardError)
        ).void
      end
      def initialize(workspace, id:, memo:, diff: nil, error: nil)
        @workspace = workspace
        @id = id
        @memo = memo
        @diff = diff
        @error = error
      end

      sig { returns(T::Boolean) }
      def success?
        error.nil?
      end

      sig { returns(T::Boolean) }
      def error?
        !error.nil?
      end
    end
  end
end
