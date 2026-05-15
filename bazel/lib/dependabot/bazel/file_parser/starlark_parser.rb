# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bazel/file_parser"

module Dependabot
  module Bazel
    class FileParser
      class StarlarkParser
        extend T::Sig

        class FunctionCall < T::Struct
          const :name, String
          const :arguments, T::Hash[String, T.untyped]
          const :positional_arguments, T::Array[T.untyped]
          const :line, Integer
        end

        sig { params(content: String).void }
        def initialize(content)
          @content = content
          @position = T.let(0, Integer)
          @line = T.let(1, Integer)
          @length = T.let(content.length, Integer)
        end

        sig { returns(T::Array[FunctionCall]) }
        def parse_function_calls
          function_calls = T.let([], T::Array[FunctionCall])

          while @position < @length
            skip_whitespace_and_comments

            next unless @position < @length

            start_position = @position
            function_call = try_parse_function_call
            function_calls << function_call if function_call

            move_to_next_char if @position == start_position
          end

          function_calls
        end

        private

        sig { returns(T.nilable(String)) }
        def current_char
          return nil if @position >= @length

          @content[@position]
        end

        sig { params(offset: Integer).returns(T.nilable(String)) }
        def peek_char(offset = 1)
          peek_pos = @position + offset
          return nil if peek_pos >= @length

          @content[peek_pos]
        end

        sig { void }
        def move_to_next_char
          @line += 1 if current_char == "\n"
          @position += 1
        end

        sig { void }
        def skip_whitespace_and_comments
          while @position < @length
            case current_char
            when /\s/
              move_to_next_char
            when "#"
              move_to_next_char while current_char && current_char != "\n"
              move_to_next_char if current_char == "\n"
            else
              break
            end
          end
        end

        sig { returns(T.nilable(FunctionCall)) }
        def try_parse_function_call
          start_line = @line

          function_name = parse_identifier
          return nil unless function_name

          skip_whitespace_and_comments

          return nil unless current_char == "("

          move_to_next_char

          keyword_arguments, positional_arguments = parse_function_arguments

          skip_whitespace_and_comments
          return nil unless current_char == ")"

          move_to_next_char

          FunctionCall.new(
            name: function_name,
            arguments: keyword_arguments,
            positional_arguments: positional_arguments,
            line: start_line
          )
        rescue StandardError
          move_to_next_char while current_char && current_char != "\n"
          move_to_next_char if current_char == "\n"
          nil
        end

        sig { returns(T.nilable(String)) }
        def parse_identifier
          return nil unless current_char&.match?(/[a-zA-Z_]/)

          identifier = T.let("", String)
          while current_char&.match?(/[a-zA-Z0-9_]/)
            char = current_char
            identifier += char if char
            move_to_next_char
          end

          identifier.empty? ? nil : identifier
        end

        sig { returns([T::Hash[String, T.untyped], T::Array[T.untyped]]) }
        def parse_function_arguments
          keyword_arguments = T.let({}, T::Hash[String, T.untyped])
          positional_arguments = T.let([], T::Array[T.untyped])

          skip_whitespace_and_comments

          return [keyword_arguments, positional_arguments] if current_char == ")"

          loop do
            skip_whitespace_and_comments
            break if current_char == ")"

            if (keyword_arg = parse_keyword_argument)
              keyword_arguments.merge!(keyword_arg)
            else
              positional_value = parse_value
              positional_arguments << positional_value if positional_value
            end

            skip_whitespace_and_comments

            break if current_char == ")"

            break unless current_char == ","

            move_to_next_char
            skip_whitespace_and_comments
          end

          [keyword_arguments, positional_arguments]
        end

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def parse_keyword_argument
          start_pos = @position
          start_line = @line

          param_name = parse_identifier
          return nil unless param_name

          skip_whitespace_and_comments

          unless current_char == "="
            @position = start_pos
            @line = start_line
            return nil
          end

          move_to_next_char
          skip_whitespace_and_comments

          value = parse_value
          return nil if value.nil?

          { param_name => value }
        end

        sig { returns(T.untyped) }
        def parse_value
          skip_whitespace_and_comments

          case current_char
          when '"', "'"
            parse_string
          when /[0-9]/
            parse_number
          when "["
            parse_array
          when /[a-zA-Z_]/
            identifier = parse_identifier
            case identifier
            when "True"
              true
            when "False"
              false
            when "None"
              nil
            else
              identifier
            end
          else
            parse_unknown_value
          end
        end

        sig { returns(T.nilable(String)) }
        def parse_string
          quote_char = current_char
          return nil unless quote_char == '"' || quote_char == "'"

          move_to_next_char
          string_value = T.let("", String)

          while current_char && current_char != quote_char
            if current_char == "\\"
              string_value += parse_escape_sequence
            elsif current_char
              string_value += T.must(current_char)
            end
            move_to_next_char
          end

          move_to_next_char if current_char == quote_char
          string_value
        end

        sig { returns(String) }
        def parse_escape_sequence
          move_to_next_char
          case current_char
          when "n"
            "\n"
          when "t"
            "\t"
          when "r"
            "\r"
          when "\\"
            "\\"
          when '"'
            '"'
          when "'"
            "'"
          else
            current_char.to_s
          end
        end

        sig { returns(T.untyped) }
        def parse_number
          number_str = T.let("", String)

          while current_char&.match?(/[0-9.]/)
            char = current_char
            number_str += char if char
            move_to_next_char
          end

          return nil if number_str.empty?

          number_str.include?(".") ? number_str.to_f : number_str.to_i
        end

        sig { returns(T.nilable(T::Array[T.untyped])) }
        def parse_array
          return nil unless current_char == "["

          move_to_next_char

          array_items = T.let([], T::Array[T.untyped])

          skip_whitespace_and_comments

          if current_char == "]"
            move_to_next_char
            return array_items
          end

          loop do
            skip_whitespace_and_comments
            break if current_char == "]"

            value = parse_value
            array_items << value if value

            skip_whitespace_and_comments

            break if current_char == "]"

            break unless current_char == ","

            move_to_next_char
            skip_whitespace_and_comments
          end

          move_to_next_char if current_char == "]"
          array_items
        end

        sig { returns(T.nilable(String)) }
        def parse_unknown_value
          value = T.let("", String)
          depth = 0

          while current_char && @position < @length
            char = current_char

            case char
            when "(", "[", "{"
              depth += 1
            when ")", "]", "}"
              break unless depth.positive?

              depth -= 1
            when ","
              break if depth.zero?

            end
            value += T.must(char)

            move_to_next_char
          end

          value.strip.empty? ? nil : value.strip
        end

        sig { void }
        def skip_to_next_argument
          depth = 0

          while current_char && @position < @length
            case current_char
            when "(", "[", "{"
              depth += 1
            when ")", "]", "}"
              break unless depth.positive?

              depth -= 1
            when ","
              break if depth.zero?

            end
            move_to_next_char
          end
        end
      end
    end
  end
end
