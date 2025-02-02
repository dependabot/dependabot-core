# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/sentry/exception_sanitizer_processor"
require "dependabot/sentry/sentry_context_processor"

module Dependabot
  module Sentry
    extend T::Sig

    # The default processor chain.
    # This chain is applied in the order of the array.
    sig { params(event: ::Sentry::Event, hint: T::Hash[Symbol, T.untyped]).returns(::Sentry::Event) }
    def self.process_chain(event, hint)
      [ExceptionSanitizer, SentryContext].each(&:new).reduce(event) do |acc, processor|
        processor.new.process(acc, hint)
      end
    end
  end
end
