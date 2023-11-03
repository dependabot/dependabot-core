# typed: false
# frozen_string_literal: true

require "raven"

# ExceptionSanitizer filters potential secrets/PII from exception payloads
class ExceptionSanitizer < Raven::Processor
  REPO = %r{[\w.\-]+/([\w.\-]+)}
  PATTERNS = {
    auth_token: /(?:authorization|bearer):? (\w+)/i,
    repo: %r{https://api\.github\.com/repos/#{REPO}|https://github\.com/#{REPO}|git@github\.com:#{REPO}}
  }.freeze

  def process(data)
    return data unless data[:exception] && data[:exception][:values]

    data[:exception][:values] = data[:exception][:values].map do |e|
      PATTERNS.each do |key, regex|
        e[:value] = e[:value].gsub(regex) do |match|
          match.sub(/#{Regexp.last_match.captures.compact.first}\z/, "[FILTERED_#{key.to_s.upcase}]")
        end
      end
      e
    end

    data
  end
end
