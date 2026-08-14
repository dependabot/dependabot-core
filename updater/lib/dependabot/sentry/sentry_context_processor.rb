# typed: strong
# frozen_string_literal: true

require "sentry-ruby"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/sentry/processor"

class SentryContext < ::Dependabot::Sentry::Processor
  sig do
    override
      .params(
        event: ::Sentry::Event,
        hint: T::Hash[Symbol, Object]
      )
      .returns(::Sentry::Event)
  end
  def process(event, hint)
    exception = hint[:exception]
    if exception.is_a?(Dependabot::HasSentryContext)
      exception.sentry_context.each do |key, value|
        event.send(:"#{key}=", value)
      end
    end
    event
  end
end
