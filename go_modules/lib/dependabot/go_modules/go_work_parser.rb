# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module GoModules
    class GoWorkParser
      extend T::Sig

      # Parses the `use` directives from go.work content.
      # Returns an array of module paths with `./` prefix stripped.
      # `"."` is included when the root module is listed.
      # Result is deduped but not sorted, filtered, or re-prefixed.
      sig { params(content: String).returns(T::Array[String]) }
      def self.use_paths(content)
        paths = T.let([], T::Array[String])

        # Multi-line use block: use (\n  ./path\n  ...\n)
        content.scan(/^use\s+\(([^)]+)\)/m).each do |block_match|
          T.must(block_match[0]).each_line do |line|
            path = line.split("//").first&.strip || ""
            next if path.empty?

            paths << path.sub(%r{^\./}, "")
          end
        end

        # Single-line use directive: use . or use ./path
        # [^\s]* (zero-or-more) so bare `use .` is captured
        content.scan(/^use\s+(?!\()(\.[^\s]*)/m).each do |match|
          path = T.must(match[0]).sub(%r{^\./}, "")
          paths << path
        end

        paths.uniq
      end
    end
  end
end
