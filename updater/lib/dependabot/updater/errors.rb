# typed: strong
# frozen_string_literal: true

require "dependabot/errors"

module Dependabot
  class Updater
    class SubprocessFailed < StandardError
      extend T::Sig
      include Dependabot::HasSentryContext

      sig { override.returns(T::Hash[Symbol, T.anything]) }
      attr_reader :sentry_context

      sig { params(message: String, sentry_context: T::Hash[Symbol, T.anything]).void }
      def initialize(message, sentry_context:)
        super(message)

        @sentry_context = sentry_context
      end
    end
  end
end
