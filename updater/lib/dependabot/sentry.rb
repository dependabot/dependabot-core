# frozen_string_literal: true

require "raven"

# ExceptionSanitizer filters potential secrets/PII from exception payloads
class ExceptionSanitizer < Raven::Processor
  REPO = %r{[\w.\-]+/([\w.\-]+)}
  PATTERNS = {
    auth_token: /(?:authorization|bearer):? (\w+)/i,
    repo: %r{api\.github\.com/repos/#{REPO}|github\.com/#{REPO}}
  }.freeze

  def process(data)
    return data unless data[:exception] && data[:exception][:values]

    data[:exception][:values] = data[:exception][:values].map do |e|
      PATTERNS.each do |key, regex|
        next unless (matches = e[:value].scan(regex))

        matches.flatten.compact.each do |match|
          e[:value] = e[:value].gsub(match, "[FILTERED_#{key.to_s.upcase}]")
        end
      end
      e
    end

    data
  end
end
