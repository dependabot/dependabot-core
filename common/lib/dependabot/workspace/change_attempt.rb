# typed: true
# frozen_string_literal: true

module Dependabot
  module Workspace
    class ChangeAttempt
      attr_reader :diff, :error, :id, :memo, :workspace

      def initialize(workspace, id:, memo:, diff: nil, error: nil)
        @workspace = workspace
        @id = id
        @memo = memo
        @diff = diff
        @error = error
      end

      def success?
        error.nil?
      end

      def error?
        error
      end
    end
  end
end
