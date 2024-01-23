# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Sentry
    class Processor
      extend T::Sig
      extend T::Helpers

      abstract!

      # Process an event before it is sent to Sentry
      sig do
        abstract
          .params(
            event: ::Sentry::Event,
            hint: T::Hash[Symbol, T.untyped]
          )
          .returns(::Sentry::Event)
      end
      def process(event, hint); end

      # The default processor chain.
      # This chain is applied in the order of the array.
      sig { params(event: ::Sentry::Event, hint: T::Hash[Symbol, T.untyped]).returns(::Sentry::Event) }
      def self.process_chain(event, hint)
        [ExceptionSanitizer, SentryContext].reduce(event) do |acc, processor|
          processor.new.process(acc, hint)
        end
      end
    end
  end
end
