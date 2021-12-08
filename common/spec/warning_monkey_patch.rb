# frozen_string_literal: true

ALLOW_PATTERNS = [
  # Ignore parser warnings for ruby 2.7 minor version mismatches
  # TODO: Fix these by upgrading to ruby 2.7.3 (requires ubuntu upgrade)
  %r{parser/current is loading parser/ruby27},
  /2.7.\d-compliant syntax, but you are running 2.7.\d/,
  %r{whitequark/parser},
  /`Faraday::Connection#authorization` is deprecated; it will be removed in version 2.0./
].freeze

# Called internally by Ruby for all warnings
module Warning
  def self.warn(message)
    $stderr.print(message)

    raise message if ENV["RAISE_ON_WARNINGS"].to_s == "true" && ALLOW_PATTERNS.none? { |pattern| pattern =~ message }

    return unless ENV["DEBUG_WARNINGS"]

    warn caller
    $stderr.puts
  end
end
