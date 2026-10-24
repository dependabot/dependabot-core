# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_parser"
require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Scans a build script once, telling string literals and comments apart,
      # and returns the code on each line that can declare a dependency:
      # - Comments are removed. Like the parser, a block comment that spans
      #   lines joins the code around it into one statement.
      # - A closure that follows a dependency declaration, like
      #   `{ because '...' }` or `{ exclude group: ... }`, is blanked, since its
      #   contents belong to other calls. Other blocks, like `dependencies {`
      #   or `if (x) {`, keep their body.
      class DeclarationScanner
        extend T::Sig

        # Calls whose block keeps its body, even when their arguments look like
        # coordinates. Kotlin's `with(x) { ... }` runs its block like `if`.
        CONTROL_KEYWORD = /\A\s*(?:if|else|for|while|when|switch|do|try|catch|finally|synchronized|with)\b/
        COORDINATES = /['"]#{FileParser::PART}:#{FileParser::PART}/
        # The parser's declaration string, after `(` or whitespace.
        VERSIONED_COORDINATES = /[(\s]['"]#{FileParser::PART}:#{FileParser::PART}:#{FileParser::VSN_PART}['"]/
        COMMENT_STARTS = %w(// /*).freeze

        # Strings that can look like `group:name` without declaring one: the
        # reason in a chained `.because(...)` call, and a project path like
        # `project("services:api")`.
        BECAUSE_ARGUMENT_REGEX = /\.\s*because\s*\(\s*(?:'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*")/
        PROJECT_PATH_REGEX = /\bproject\s*\(\s*(?:path\s*[:=]\s*)?['"][^'"\n]*['"]/

        sig { params(key: String, quoted_value: String).returns(Regexp) }
        def self.map_argument_regex(key, quoted_value)
          /(?:^|[\s,({])(?:#{key}|'#{key}'|"#{key}")\s*(?:=|:)\s*['"]#{quoted_value}['"]/
        end

        sig { params(code: String).returns(String) }
        def self.without_non_declaring_strings(code)
          code.gsub(BECAUSE_ARGUMENT_REGEX, "").gsub(PROJECT_PATH_REGEX, "")
        end

        # Whether the code declares any dependency, either as a coordinate
        # string or with `group` and `name` arguments.
        sig { params(code: String).returns(T::Boolean) }
        def self.declares_any_coordinates?(code)
          code = without_non_declaring_strings(code)
          code.match?(COORDINATES) || declares_group_and_name?(code)
        end

        sig { params(code: String).returns(T::Boolean) }
        def self.declares_group_and_name?(code)
          code.match?(map_argument_regex("group", "[^'\"]+")) && code.match?(map_argument_regex("name", "[^'\"]+"))
        end

        sig { params(content: String, kotlin: T::Boolean).void }
        def initialize(content, kotlin:)
          # The code without comments, and the code without comments or strings
          # (used to find brackets). Both keep every offset and newline.
          @code = T.let(content.dup, String)
          @skeleton = T.let(content.dup, String)
          @joining_newlines = T.let(Set.new, T::Set[Integer])
          blank_literals_and_comments(content, kotlin)
          blank_declaration_closures
        end

        # Returns each line's code, and the index of the statement it belongs
        # to (lines joined by a block comment share one).
        sig { returns([T::Array[String], T::Array[Integer]]) }
        def code_by_line
          statement = 0
          statement_of = [statement]
          @code.each_char.with_index do |char, index|
            next unless char == "\n"

            statement += 1 unless @joining_newlines.include?(index)
            statement_of << statement
          end
          [@code.split("\n", -1), statement_of]
        end

        private

        sig { params(content: String, kotlin: T::Boolean).void }
        def blank_literals_and_comments(content, kotlin)
          index = 0
          while index < content.length
            stop = comment_or_literal_end(content, index, kotlin)
            if stop.nil? || unterminated_quote?(content, index, stop)
              index += 1
              next
            end

            comment = COMMENT_STARTS.include?(content[index, 2])
            (index...stop).each do |position|
              if content[position] == "\n"
                @joining_newlines << position if comment
              else
                @skeleton[position] = " "
                @code[position] = " " if comment
              end
            end
            index = stop
          end
        end

        # Block comments end at the first `*/`, even in Kotlin, to match the
        # parser, which removes them with a regex.
        sig { params(content: String, index: Integer, kotlin: T::Boolean).returns(T.nilable(Integer)) }
        def comment_or_literal_end(content, index, kotlin)
          return FileParser.block_comment_end(content, index, content.length) if content[index, 2] == "/*"

          FileParser.literal_or_comment_end(content, index, content.length, kotlin: kotlin)
        end

        # A quote string can't span lines, so a quote whose string would run
        # past the end of the line (like the one in `// don't`) is just a quote.
        sig { params(content: String, index: Integer, stop: Integer).returns(T::Boolean) }
        def unterminated_quote?(content, index, stop)
          quote = content[index]
          %w(' ").include?(quote) && content[index, 3] != T.must(quote) * 3 &&
            T.must(content[index...stop]).include?("\n")
        end

        # Tracks brackets outside strings and comments. A statement starts after
        # `{`, `}`, `;` or a newline outside any brackets; a newline inside a
        # block comment doesn't end it. A `{` right after a call (`)` or `,`)
        # whose statement so far declares a dependency opens that declaration's
        # closure, which is blanked. Chained calls like `.also {` are kept.
        sig { void }
        def blank_declaration_closures
          open_blocks = T.let([], T::Array[[Integer, Integer, T::Boolean]])
          statement_start = 0
          depth = 0
          @skeleton.each_char.with_index do |char, index|
            case char
            when "(", "[" then depth += 1
            when ")", "]" then depth -= 1 if depth.positive?
            when "{"
              open_blocks << [index, depth, declaration?(T.must(@code[statement_start...index]))]
              statement_start = index + 1
              depth = 0
            when "}"
              open, outer_depth, closure = open_blocks.pop
              blank(open + 1, index) if open && closure
              depth = outer_depth || 0
              statement_start = index + 1
            when ";", "\n"
              statement_start = index + 1 if depth.zero? && !@joining_newlines.include?(index)
            end
          end
        end

        # Like the parser, a declaration has a `group:name:version` string or
        # `group` and `name` arguments. Calls that take only `group:name`, like
        # `withModule("group:name") { ... }`, keep their body.
        sig { params(owner: String).returns(T::Boolean) }
        def declaration?(owner)
          owner = DeclarationScanner.without_non_declaring_strings(owner)
          owner.rstrip.end_with?(")", ",") && !owner.match?(CONTROL_KEYWORD) &&
            (owner.match?(VERSIONED_COORDINATES) ||
              DeclarationScanner.declares_group_and_name?(owner))
        end

        sig { params(start: Integer, stop: Integer).void }
        def blank(start, stop)
          (start...stop).each { |position| @code[position] = " " unless @code[position] == "\n" }
        end
      end
    end
  end
end
