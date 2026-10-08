# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    # pnpm 12 prints errors as a bordered block that is hard-wrapped at 80 columns, splitting URLs and package names
    # mid-token, instead of pnpm 11's single `[ERR_PNPM_X] message` line:
    #
    #   Error: ERR_PNPM_FETCH_401
    #
    #     × installing dependencies
    #     ├─▶ Failed to resolve dependency tree: GET https://npm.pkg.github.com/@dsp-
    #     │   testing%2Fpkg: Unauthorized - 401
    #     ╰─▶ GET https://npm.pkg.github.com/@dsp-testing%2Fpkg: Unauthorized - 401
    #     help: No authorization header was set for the request.
    #
    # `normalize` rewrites that block into the pnpm 11 layout so one set of patterns matches both. Messages in any
    # other format are returned unchanged.
    module PnpmErrorMessage
      extend T::Sig

      HEADER = /^Error:[ \t]*+(?:(?<code>ERR_PNPM_[A-Z0-9_]+)[ \t]*+)?(?<rest>.*)$/
      HEADLINE = /\A\s*×/
      MARKER = /\A\s*(?:├─▶|╰─▶|help:)[ \t]?(?<text>.*)\z/
      GUTTER = /\A\s*│[ \t]?(?<text>.*)\z/
      # pnpm wraps after a hyphen or slash without adding a space, and at a space by dropping it
      JOINS_WITHOUT_SPACE = %r{\S[-/]\z}
      # A token longer than a line is cut at the line width (72 characters of text) wherever it falls
      HARD_WRAP_WIDTH = 72

      sig { params(message: String).returns(String) }
      def self.normalize(message)
        header = HEADER.match(message)
        return message unless header && message.include?("×")

        lines = [header[:rest].to_s, *T.must(message[header.end(0)..]).lines.map(&:chomp)]
        body = unwrap(lines)
        return message if body.empty?

        first = header[:code] ? "[#{header[:code]}] #{body.first}" : body.first.to_s
        "#{message[0, header.begin(0)]}#{[first, *body.drop(1)].join("\n")}"
      end

      sig { params(lines: T::Array[String]).returns(T::Array[String]) }
      def self.unwrap(lines)
        logical = T.let([], T::Array[String])
        continuing = T.let(false, T::Boolean)
        previous_chunk = T.let("", String)

        lines.each do |line|
          if HEADLINE.match?(line)
            continuing = false
          elsif (marker = MARKER.match(line))
            previous_chunk = marker[:text].to_s.strip
            logical << previous_chunk
            continuing = true
          else
            chunk = ((gutter = GUTTER.match(line)) ? gutter[:text] : line).to_s.strip
            if chunk.empty?
              continuing = false
            elsif continuing
              logical[-1] = join_wrapped(T.must(logical.last), previous_chunk, chunk)
              previous_chunk = chunk
            else
              logical << chunk
              previous_chunk = chunk
              continuing = true
            end
          end
        end

        logical
      end
      private_class_method :unwrap

      sig { params(previous: String, previous_chunk: String, chunk: String).returns(String) }
      def self.join_wrapped(previous, previous_chunk, chunk)
        cut_inside_token = previous.match?(JOINS_WITHOUT_SPACE) ||
                           (previous_chunk.length >= HARD_WRAP_WIDTH && previous_chunk.match?(/\A\S+\z/))

        cut_inside_token ? "#{previous}#{chunk}" : "#{previous} #{chunk}"
      end
      private_class_method :join_wrapped
    end
  end
end
