# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Updater
    class SubprocessFailed < StandardError
      extend T::Sig

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :sentry_context

      sig { params(message: String, sentry_context: T::Hash[Symbol, T.untyped]).void }
      def initialize(message, sentry_context:)
        super(message)

        @sentry_context = sentry_context
      end
    end
  end
end
