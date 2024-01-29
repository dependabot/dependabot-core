# typed: strict
# frozen_string_literal: true

require "sentry-ruby"
require "sorbet-runtime"

require "dependabot/sentry/processor"

class SentryContext < ::Dependabot::Sentry::Processor
  sig do
    override
      .params(
        event: ::Sentry::Event,
        hint: T::Hash[Symbol, T.untyped]
      )
      .returns(::Sentry::Event)
  end
  def process(event, hint)
    if (exception = hint[:exception]) && exception.respond_to?(:sentry_context)
      exception.sentry_context&.each do |key, value|
        event.send("#{key}=", value)
      end
    end
    event
  end
end
