# frozen_string_literal: true

ALLOW_PATTERNS = [
  # Ignore warnings for mismatches between `parser/current` and our
  # current patch version of ruby. This is a recurring issue that occurs
  # whenever the parser gets ahead of our installed ruby version.
  %r{parser/current is loading parser/ruby31},
  /3.1.\d-compliant syntax, but you are running 3.1.\d/,
  %r{whitequark/parser}
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
