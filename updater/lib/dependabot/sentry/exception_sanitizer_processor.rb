# typed: strong
# frozen_string_literal: true

require "sentry-ruby"
require "sorbet-runtime"

require "dependabot/sentry/processor"

# ExceptionSanitizer filters potential secrets/PII from exception payloads
class ExceptionSanitizer < ::Dependabot::Sentry::Processor
  extend T::Sig

  REPO = %r{[\w.\-]+/([\w.\-]+)}
  PATTERNS = T.let(
    {
      auth_token: /(?:authorization|bearer):? (\w+)/i,
      repo: %r{https://api\.github\.com/repos/#{REPO}|https://github\.com/#{REPO}|git@github\.com:#{REPO}}
    }.freeze,
    T::Hash[Symbol, Regexp]
  )

  sig do
    override
      .params(
        event: ::Sentry::Event,
        _hint: T::Hash[Symbol, T.untyped]
      )
      .returns(::Sentry::Event)
  end
  def process(event, _hint)
    return event unless event.is_a?(::Sentry::ErrorEvent)

    event.exception.values.each do |e|
      PATTERNS.each do |key, regex|
        e.value = e.value.gsub(regex) do |match|
          match.sub(/#{T.must(Regexp.last_match).captures.compact.first}\z/, "[FILTERED_#{key.to_s.upcase}]")
        end
      end
    end

    event
  end
end
