# typed: false
# frozen_string_literal: true

module Dependabot
  class Updater
    class SubprocessFailed < StandardError
      attr_reader :raven_context

      def initialize(message, raven_context:)
        super(message)

        @raven_context = raven_context
      end
    end
  end
end
