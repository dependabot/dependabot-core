# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/powershell/file_parser"

module Dependabot
  module Powershell
    class FileParser < Dependabot::FileParsers::Base
      # Parses the `RequiredModules` array from a PowerShell module manifest
      # (`.psd1`) file into a list of ModuleDeclaration objects.
      #
      # https://learn.microsoft.com/powershell/module/microsoft.powershell.core/new-modulemanifest
      class Psd1ManifestParser
        extend T::Sig

        REQUIRED_MODULES_KEY = /RequiredModules\s*=\s*/i

        sig { params(file: Dependabot::DependencyFile).void }
        def initialize(file:)
          @file = file
        end

        sig { returns(T::Array[ModuleDeclaration]) }
        def parse
          required_modules_entries.filter_map do |entry|
            ModuleSpecificationParser.parse(entry, declaration_type: :required_modules)
          end
        end

        private

        # Locates the `RequiredModules = ...` assignment and returns the
        # individual entries it declares, regardless of whether it's written
        # as an array (`@(...)`), a single hashtable (`@{...}`), or a single
        # bare/quoted module name (`'Pester'`).
        sig { returns(T::Array[String]) }
        def required_modules_entries
          content = T.must(@file.content)
          match = REQUIRED_MODULES_KEY.match(content)
          return [] unless match

          value_start = match.end(0)
          rest = T.must(content[value_start..])

          if rest.start_with?("@(")
            array_entries(content, value_start)
          elsif rest.start_with?("@{")
            hashtable_entry(content, value_start)
          elsif rest.start_with?("'", "\"")
            scalar_entry(rest)
          else
            []
          end
        end

        sig { params(content: String, value_start: Integer).returns(T::Array[String]) }
        def array_entries(content, value_start)
          body = extract_balanced(content, value_start + 1)
          return [] unless body

          ModuleSpecificationParser.split_entries(strip_line_comments(body))
        end

        sig { params(content: String, value_start: Integer).returns(T::Array[String]) }
        def hashtable_entry(content, value_start)
          inner = extract_balanced(content, value_start + 1)
          return [] unless inner

          ["@{#{inner}}"]
        end

        sig { params(rest: String).returns(T::Array[String]) }
        def scalar_entry(rest)
          entry = extract_quoted_scalar(rest)
          entry ? [entry] : []
        end

        # Removes `# ...` line comments from `text`, leaving quoted strings
        # (which may themselves contain a `#`) untouched. Applied before
        # splitting an array's body into entries so a comment trailing one
        # entry doesn't get attached to the next.
        sig { params(text: String).returns(String) }
        def strip_line_comments(text)
          result = +""
          quote = T.let(nil, T.nilable(String))
          in_comment = T.let(false, T::Boolean)

          text.each_char do |char|
            if in_comment
              in_comment = false if char == "\n"
              result << char if char == "\n"
              next
            end

            if quote
              result << char
              quote = nil if char == quote
              next
            end

            case char
            when "'", "\""
              quote = char
              result << char
            when "#"
              in_comment = true
            else
              result << char
            end
          end

          result
        end

        # Given text starting with a `'` or `"`, returns the quoted scalar
        # (including its quotes), respecting PowerShell's doubled-quote
        # escape (e.g. `'It''s'`).
        sig { params(text: String).returns(T.nilable(String)) }
        def extract_quoted_scalar(text)
          quote = text[0]
          return nil unless quote

          index = 1
          while index < text.length
            char = text[index]
            if char == quote
              if text[index + 1] == quote
                index += 2
                next
              end
              return text[0..index]
            end
            index += 1
          end

          nil
        end

        # Given content and the index of an opening `(` or `{` character,
        # returns the substring between it and its matching closing `)`/`}`,
        # respecting quoted strings and nested braces/parens so that nested
        # `@{...}` hashtable entries don't prematurely close the array.
        sig { params(content: String, open_index: Integer).returns(T.nilable(String)) }
        def extract_balanced(content, open_index)
          depth = 0
          quote = T.let(nil, T.nilable(String))
          start_index = open_index + 1

          T.must(content[open_index..]).each_char.with_index(open_index) do |char, index|
            if quote
              quote = nil if char == quote
              next
            end

            case char
            when "'", "\""
              quote = char
            when "{", "("
              depth += 1
            when "}", ")"
              depth -= 1
              return content[start_index...index] if depth.zero?
            end
          end

          nil
        end
      end
    end
  end
end
