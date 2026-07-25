# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Powershell
    # Masks the lexically inert regions of PowerShell source text - block
    # comments (`<# ... #>`), line comments (`# ...`), and here-strings
    # (`@"..."@` / `@'...'@`) - by replacing them with equal-length
    # whitespace (newlines preserved), while leaving real code (including
    # quoted strings) untouched.
    #
    # Every declaration scanner in this ecosystem (RequiresDirectiveParser,
    # Psd1ManifestParser, DeclarationLocator, FileFetcher) runs its regexes
    # against masked content instead of the raw file, so a `#Requires
    # -Modules` directive or `RequiredModules = ...` assignment that's only
    # written inside a comment, a documentation example, or a here-string -
    # rather than as active code - is never mistaken for a real declaration.
    # Masking (rather than stripping) keeps every absolute offset in the
    # returned string aligned with the original content, which
    # `DeclarationLocator` depends on for in-place rewriting.
    #
    # `#Requires -Modules ...` is a directive, not a comment, even though it
    # begins with `#` - so an active directive line (whitespace then
    # literally `#Requires -Modules`, matching RequiresDirectiveParser's own
    # anchor) is left unmasked; anything else starting with `#` is treated
    # as a regular comment.
    #
    # Implemented as a single left-to-right scan using only direct
    # character/substring access (no regex backtracking), so it runs in
    # linear time even on adversarial input such as many repetitions of an
    # unterminated `<#`.
    #
    # `.mask_quoted_strings` provides a second, narrower pass on top of
    # `.mask`'s output: it additionally blanks the interior of quoted
    # strings so a caller locating a bare hashtable key (e.g.
    # `RequiredModules =`) can't match one that only appears inside a
    # string value (e.g. a `Description` field mentioning it as an
    # example). Its output must only be used to find a match's position -
    # actual entries/values must still be read from `.mask`'s output.
    class ContentMasker
      extend T::Sig

      REQUIRES_DIRECTIVE = /\A#Requires\s+-Modules\b/i

      sig { params(content: String).returns(String) }
      def self.mask(content)
        line_starts = build_line_starts(content)
        length = content.length
        result = +""
        index = 0

        index = advance(content, result, index, line_starts) while index < length

        result
      end

      # Given content already processed by `.mask` (so comments and
      # here-strings are already blanked), additionally blanks the
      # *interior* of every quoted string - preserving its opening/closing
      # delimiters, newlines, and overall length - so a caller searching
      # for a bare keyword (e.g. the `RequiredModules =` hashtable key)
      # can't match text that merely appears inside a string value, such
      # as a `Description` field that mentions `RequiredModules = @(...)`
      # as a documentation example.
      #
      # The result is for locating a match's *position* only: because
      # quoted values are blanked, it must never be used to read out the
      # actual entries/values a match locates - re-slice the original
      # (comment-masked but quote-intact) content at the returned offsets
      # instead.
      sig { params(content: String).returns(String) }
      def self.mask_quoted_strings(content)
        length = content.length
        result = +""
        index = 0

        while index < length
          char = T.must(content[index])

          index = if char == "'" || char == "\""
                    blank_quoted(content, result, index, char)
                  else
                    result << char
                    index + 1
                  end
        end

        result
      end

      # Dispatches on the character(s) at `index`: opens/masks a block
      # comment, here-string, or line comment; copies a quoted string
      # through untouched; or copies a single ordinary character. Returns
      # the index to resume scanning from.
      sig do
        params(
          content: String,
          result: String,
          index: Integer,
          line_starts: T::Array[Integer]
        ).returns(Integer)
      end
      def self.advance(content, result, index, line_starts)
        two = content[index, 2]

        return mask_block_comment(content, result, index) if two == "<#"

        return mask_here_string(content, result, index, "\"") if two == "@\"" && here_string_opener?(content, index + 2)

        return mask_here_string(content, result, index, "'") if two == "@'" && here_string_opener?(content, index + 2)

        case content[index]
        when "#"
          mask_hash(content, result, index, line_starts)
        when "'"
          copy_quoted(content, result, index, "'")
        when "\""
          copy_quoted(content, result, index, "\"")
        else
          result << T.must(content[index])
          index + 1
        end
      end
      private_class_method :advance

      # Precomputes, for every offset, the offset its line begins at - so
      # checking "is this `#` the first non-whitespace character on its
      # line" (required to recognize an active `#Requires` directive) never
      # needs to rescan backwards through the file.
      sig { params(content: String).returns(T::Array[Integer]) }
      def self.build_line_starts(content)
        line_starts = Array.new(content.length, 0)
        current_line_start = 0

        content.each_char.with_index do |char, index|
          line_starts[index] = current_line_start
          current_line_start = index + 1 if char == "\n"
        end

        line_starts
      end
      private_class_method :build_line_starts

      # Handles a `#` seen outside of any string/comment: either it opens an
      # active `#Requires -Modules` directive (left untouched, so
      # RequiresDirectiveParser/DeclarationLocator can still find it) or a
      # regular line comment (masked through end of line).
      sig { params(content: String, result: String, index: Integer, line_starts: T::Array[Integer]).returns(Integer) }
      def self.mask_hash(content, result, index, line_starts)
        if requires_directive_line?(content, index, line_starts)
          result << "#"
          index + 1
        else
          mask_line_comment(content, result, index)
        end
      end
      private_class_method :mask_hash

      # True when `index` (a `#`) is the first non-whitespace character on
      # its line and the rest of that line matches
      # RequiresDirectiveParser::REQUIRES_MODULES_LINE's own anchor, i.e.
      # it's an active directive rather than a comment that merely mentions
      # `#Requires`.
      sig { params(content: String, index: Integer, line_starts: T::Array[Integer]).returns(T::Boolean) }
      def self.requires_directive_line?(content, index, line_starts)
        line_start = T.must(line_starts[index])
        return false unless T.must(content[line_start...index]).strip.empty?

        newline_index = content.index("\n", index)
        line_end = newline_index || content.length
        !!T.must(content[index...line_end]).match?(REQUIRES_DIRECTIVE)
      end
      private_class_method :requires_directive_line?

      sig { params(content: String, result: String, index: Integer).returns(Integer) }
      def self.mask_line_comment(content, result, index)
        newline_index = content.index("\n", index)
        end_index = newline_index || content.length
        result << (" " * (end_index - index))
        end_index
      end
      private_class_method :mask_line_comment

      sig { params(content: String, result: String, index: Integer).returns(Integer) }
      def self.mask_block_comment(content, result, index)
        close_index = content.index("#>", index + 2)
        end_index = close_index ? close_index + 2 : content.length
        T.must(content[index...end_index]).each_char { |char| result << (char == "\n" ? "\n" : " ") }
        end_index
      end
      private_class_method :mask_block_comment

      # True when, starting at `index` (the position right after a `@"` or
      # `@'` opener), the rest of the current line is empty/whitespace -
      # PowerShell requires a here-string opener to be the last thing on its
      # line.
      sig { params(content: String, index: Integer).returns(T::Boolean) }
      def self.here_string_opener?(content, index)
        i = index
        length = content.length
        i += 1 while i < length && (content[i] == " " || content[i] == "\t" || content[i] == "\r")
        i >= length || content[i] == "\n"
      end
      private_class_method :here_string_opener?

      # Masks a here-string, from its `@"`/`@'` opener through the closing
      # `"@`/`'@` (which PowerShell requires to be the first non-whitespace
      # sequence on its line), inclusive. If unterminated, masks through the
      # end of the content.
      sig { params(content: String, result: String, start_index: Integer, closing_char: String).returns(Integer) }
      def self.mask_here_string(content, result, start_index, closing_char)
        length = content.length
        search_from = start_index + 2
        end_index = length

        loop do
          newline_index = content.index("\n", search_from)
          break unless newline_index

          line_start = newline_index + 1
          i = line_start
          i += 1 while i < length && (content[i] == " " || content[i] == "\t")

          if content[i] == closing_char && content[i + 1] == "@"
            end_index = i + 2
            break
          end

          search_from = line_start
        end

        T.must(content[start_index...end_index]).each_char { |char| result << (char == "\n" ? "\n" : " ") }
        end_index
      end
      private_class_method :mask_here_string

      # Copies a single/double-quoted string through untouched (so its
      # content is never mistaken for a comment/here-string marker),
      # respecting PowerShell's escaping rules: a doubled quote (`''`/`""`)
      # is a literal quote in either style, and a backtick additionally
      # escapes the following character in a double-quoted string.
      sig { params(content: String, result: String, index: Integer, quote_char: String).returns(Integer) }
      def self.copy_quoted(content, result, index, quote_char)
        length = content.length
        result << T.must(content[index])
        i = index + 1

        while i < length
          char = T.must(content[i])

          if quote_char == "\"" && char == "`" && i + 1 < length
            result << char << T.must(content[i + 1])
            i += 2
            next
          end

          if char == quote_char
            if content[i + 1] == quote_char
              result << char << quote_char
              i += 2
              next
            end

            result << char
            i += 1
            break
          end

          result << char
          i += 1
        end

        i
      end
      private_class_method :copy_quoted

      # Blanks the interior of a single/double-quoted string (keeping its
      # delimiters), used by `.mask_quoted_strings`. Unlike `.copy_quoted`,
      # backtick escapes aren't treated specially - the result is only used
      # for locating keywords outside of strings, so it just needs to keep
      # the same length and correctly find the real closing quote.
      sig { params(content: String, result: String, index: Integer, quote_char: String).returns(Integer) }
      def self.blank_quoted(content, result, index, quote_char)
        length = content.length
        result << T.must(content[index])
        i = index + 1

        while i < length
          char = T.must(content[i])

          if char == quote_char && content[i + 1] == quote_char
            result << "  "
            i += 2
            next
          end

          if char == quote_char
            result << char
            i += 1
            break
          end

          result << (char == "\n" ? "\n" : " ")
          i += 1
        end

        i
      end
      private_class_method :blank_quoted
    end
  end
end
