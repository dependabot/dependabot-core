# frozen_string_literal: true

# ExceptionSanitizer filters potential secrets/PII from exception payloads
class ExceptionSanitizer
  REPO = %r{[\w.\-]+/([\w.\-]+)}
  PATTERNS = {
    auth_token: /(?:authorization|bearer):? (\w+)/i,
    repo: %r{api\.github\.com/repos/#{REPO}|github\.com/#{REPO}}
  }.freeze

  def self.sanitize_sentry_exception_event(event, hint)
    debugger
    return event unless hint[:exception]

    event.exception.values = event.exception.values.map do |e|
      PATTERNS.each do |key, regex|
        next unless (matches = e.value.scan(regex))

        matches.flatten.compact.each do |match|
          e.value = e.value.gsub(match, "[FILTERED_#{key.to_s.upcase}]"))
        end
      end
      e
    end

    event
  end
end
