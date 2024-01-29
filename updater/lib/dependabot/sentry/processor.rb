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
    end
  end
end
