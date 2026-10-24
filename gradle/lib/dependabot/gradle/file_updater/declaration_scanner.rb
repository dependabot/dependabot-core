# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "strscan"

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
        # coordinates: control flow (Kotlin's `with(x) { ... }` runs its block
        # like `if`), project blocks, and `because` reasons.
        KEEP_BODY_CALLS = T.let(
          %w(if for while when switch catch synchronized with project because).to_set.freeze,
          T::Set[String]
        )
        COORDINATES = /['"]#{FileParser::PART}:#{FileParser::PART}/
        # The parser's declaration string, after `(` or whitespace.
        VERSIONED_COORDINATES = /[(\s]['"]#{FileParser::PART}:#{FileParser::PART}:#{FileParser::VSN_PART}['"]/
        COMMENT_STARTS = %w(// /*).freeze

        # Strings that can look like `group:name` without declaring one: the
        # reason in a chained `.because(...)` call, and a project path like
        # `project("services:api")`.
        # Triple-quoted strings are matched whole first, so their quotes can't
        # pass for an empty string. Like the parser, they end at the next
        # triple quote.
        STRING_LITERAL = /
          """(?:(?!""").)*"""|
          '''(?:(?!''').)*'''|
          '(?:\\.|[^'\\\n])*'|
          "(?:\\.|[^"\\\n])*"
        /mx
        BECAUSE_ARGUMENT_REGEX = /\.\s*because\s*\(\s*(?:#{STRING_LITERAL})/
        PROJECT_PATH_REGEX = /\bproject\s*\(\s*(?:path\s*[:=]\s*)?(?:#{STRING_LITERAL})/

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

        # Like the parser, `group` and `name` must be arguments of the same
        # call, so a chained `.exclude(group = ...)` or a wrapped
        # `create(name = ...)` can't supply the other one.
        sig { params(code: String, group: String, name: String).returns(T::Boolean) }
        def self.declares_group_and_name?(code, group: "[^'\"]+", name: "[^'\"]+")
          calls(code).any? do |call|
            call.match?(map_argument_regex("group", group)) && call.match?(map_argument_regex("name", name))
          end
        end

        # Returns each call's own arguments, without the calls or closures
        # nested in them, plus the code outside any call. Brackets inside
        # string literals are ignored.
        sig { params(code: String).returns(T::Array[String]) }
        def self.calls(code)
          finished = T.let([], T::Array[String])
          open = T.let([+""], T::Array[String])
          scanner = StringScanner.new(code)
          until scanner.eos?
            literal = scanner.scan(STRING_LITERAL)
            next T.must(open.last) << literal if literal

            char = T.must(scanner.getch)
            if "({".include?(char)
              T.must(open.last) << " "
              open << +""
            elsif ")}".include?(char) && open.length > 1
              finished << T.must(open.pop)
            else
              T.must(open.last) << char
            end
          end
          finished + open
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
              open_blocks << [index, depth, declaration?(statement_start, index)]
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
        # `group` and `name` arguments. Only the call that owns the block counts,
        # so `implementation("a:b:1").also() { ... }` and calls that take only
        # `group:name`, like `withModule("group:name") { ... }`, keep their body.
        sig { params(start: Integer, stop: Integer).returns(T::Boolean) }
        def declaration?(start, stop)
          owner = owning_call(start, stop)
          return false unless owner

          name, arguments = owner
          return false if KEEP_BODY_CALLS.include?(name)

          arguments = "(#{DeclarationScanner.without_non_declaring_strings(arguments)})"
          arguments.match?(VERSIONED_COORDINATES) || DeclarationScanner.declares_group_and_name?(arguments)
        end

        # The call that a block between start and stop belongs to, and its
        # arguments. The block follows the call's `(...)`, or is its last
        # argument after a `,`. The call may be qualified or assigned
        # (`kotlin.with(x) {`, `val r = with(x) {`).
        sig { params(start: Integer, stop: Integer).returns(T.nilable([String, String])) }
        def owning_call(start, stop)
          before = T.must(@skeleton[start...stop]).rstrip
          last = start + before.length - 1
          return unless before.end_with?(")", ",")

          open = unmatched_open(start, last - 1)
          if open
            arguments_end = before.end_with?(")") ? last : stop
            name = @skeleton[start...open].to_s[/(\w+)\s*\z/, 1]
          else
            return if before.end_with?(")")

            open = start - 1
            arguments_end = stop
            name = @skeleton[start...stop].to_s[/\A\s*(\w+)/, 1]
          end
          [name.to_s, T.must(@code[(open + 1)...arguments_end])]
        end

        # The nearest `(` before `from` that isn't closed by `from`.
        sig { params(start: Integer, from: Integer).returns(T.nilable(Integer)) }
        def unmatched_open(start, from)
          depth = 0
          from.downto(start) do |index|
            case @skeleton[index]
            when ")" then depth += 1
            when "("
              return index if depth.zero?

              depth -= 1
            end
          end
          nil
        end

        sig { params(start: Integer, stop: Integer).void }
        def blank(start, stop)
          (start...stop).each { |position| @code[position] = " " unless @code[position] == "\n" }
        end
      end
    end
  end
end
