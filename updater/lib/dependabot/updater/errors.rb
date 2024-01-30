# typed: true
# frozen_string_literal: true

module Dependabot
  class Updater
    class SubprocessFailed < StandardError
      attr_reader :sentry_context

      def initialize(message, sentry_context:)
        super(message)

        @sentry_context = sentry_context
      end
    end
  end
end
