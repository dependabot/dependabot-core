# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

module Dependabot
  module Cargo
    module TomlParser
      extend T::Sig

      sig { params(content: String).returns(T::Hash[T.untyped, T.untyped]) }
      def self.parse(content)
        TomlRB.parse(content)
      rescue TomlRB::ParseError
        TomlRB.parse(normalize_multiline_inline_tables(content))
      end

      sig { params(content: String).returns(String) }
      def self.normalize_multiline_inline_tables(content)
        replacement_ranges = T.let([], T::Array[[Integer, Integer, String]])

        index = T.let(0, Integer)
        while index < content.length
          unless content[index] == "="
            index += 1
            next
          end

          open_brace = skip_whitespace(content, index + 1)
          unless open_brace < content.length && content[open_brace] == "{"
            index += 1
            next
          end

          close_brace = find_matching_brace(content, open_brace)
          unless close_brace
            index += 1
            next
          end

          segment = T.must(content[open_brace..close_brace])
          replacement_ranges << [open_brace, close_brace, normalize_inline_table(segment)] if segment.include?("\n")

          index = close_brace + 1
        end

        return content if replacement_ranges.empty?

        normalized_content = content.dup
        replacement_ranges.reverse_each do |start_idx, end_idx, replacement|
          normalized_content[start_idx..end_idx] = replacement
        end

        normalized_content
      end

      sig { params(content: String, index: Integer).returns(Integer) }
      def self.skip_whitespace(content, index)
        index += 1 while index < content.length && T.must(content[index]).match?(/\s/)

        index
      end

      # This parser is intentionally a character-level state machine.
      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(content: String, open_brace_index: Integer).returns(T.nilable(Integer)) }
      def self.find_matching_brace(content, open_brace_index)
        depth = T.let(0, Integer)
        in_string = T.let(false, T::Boolean)
        quote_char = T.let(nil, T.nilable(String))
        escaped = T.let(false, T::Boolean)

        index = T.let(open_brace_index, Integer)
        while index < content.length
          char = content[index]

          if in_string
            if escaped
              escaped = false
            elsif char == "\\"
              escaped = true
            elsif char == quote_char
              in_string = false
            end
          elsif char == '"' || char == "'"
            in_string = true
            quote_char = char
          elsif char == "{"
            depth += 1
          elsif char == "}"
            depth -= 1
            return index if depth.zero?
          elsif char == "#"
            next_newline = content.index("\n", index)
            index = next_newline || content.length
            next
          end

          index += 1
        end

        nil
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(segment: String).returns(String) }
      def self.normalize_inline_table(segment)
        inner = T.must(segment[1...-1])
        squished_inner = squish_whitespace_outside_strings(inner)
        squished_inner = squished_inner.sub(/,\s*\z/, "")

        "{ #{squished_inner.strip} }"
      end

      # This parser is intentionally a character-level state machine.
      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(content: String).returns(String) }
      def self.squish_whitespace_outside_strings(content)
        output = +""
        in_string = T.let(false, T::Boolean)
        quote_char = T.let(nil, T.nilable(String))
        escaped = T.let(false, T::Boolean)
        pending_space = T.let(false, T::Boolean)

        content.each_char do |char|
          if in_string
            output << char
            if escaped
              escaped = false
            elsif char == "\\"
              escaped = true
            elsif char == quote_char
              in_string = false
            end
            next
          end

          if char.match?(/\s/)
            pending_space = true
            next
          end

          output << " " if pending_space && !output.empty?
          pending_space = false

          if char == '"' || char == "'"
            in_string = true
            quote_char = char
          end

          output << char
        end

        output
      end
      # rubocop:enable Metrics/PerceivedComplexity
    end
  end
end
