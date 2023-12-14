# typed: strong
# frozen_string_literal: true

require "raven"
require "sorbet-runtime"

# ExceptionSanitizer filters potential secrets/PII from exception payloads
class ExceptionSanitizer < Raven::Processor
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
    params(data: T::Hash[Symbol, T.nilable(T::Hash[Symbol, T::Array[T::Hash[Symbol, String]]])])
      .returns(T::Hash[Symbol, T.untyped])
  end
  def process(data)
    return data unless data.dig(:exception, :values)

    T.must(data[:exception])[:values] = T.must(data.dig(:exception, :values)).map do |e|
      PATTERNS.each do |key, regex|
        e[:value] = T.must(e[:value]).gsub(regex) do |match|
          match.sub(/#{T.must(Regexp.last_match).captures.compact.first}\z/, "[FILTERED_#{key.to_s.upcase}]")
        end
      end
      e
    end

    data
  end
end
