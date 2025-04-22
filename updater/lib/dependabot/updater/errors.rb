# typed: strong
# frozen_string_literal: true

module Dependabot
  class Updater
    class SubprocessFailed < StandardError
      extend T::Sig

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :sentry_context

      sig { params(message: String, sentry_context: T::Hash[Symbol, T.untyped]).void }
      def initialize(message, sentry_context:)
        super(message)

        @sentry_context = T.let(sentry_context, T::Hash[Symbol, T.untyped])
      end
    end
  end
end
