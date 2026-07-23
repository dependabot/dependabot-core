# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/powershell/file_updater"
require "dependabot/powershell/file_parser/module_specification_parser"

module Dependabot
  module Powershell
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Re-scans a dependency file's raw content for the same module
      # declarations the stage-3 parser would find, but additionally records
      # each declaration's absolute character offsets. The parser itself
      # only needs to produce dependency metadata, so it never tracked
      # position - the file updater needs it to rewrite a specific
      # declaration in place without disturbing anything around it.
      class DeclarationLocator
        extend T::Sig

        # A single module declaration found in the file, with the absolute
        # (start...end) offsets of its raw (trimmed) source text.
        class Occurrence < T::Struct
          const :name, String
          const :style, Symbol
          const :version_key, T.nilable(String)
          const :start_index, Integer
          const :end_index, Integer
        end

        REQUIRES_MODULES_LINE = /^\s*#Requires\s+-Modules\s+(?<modules>.+)$/i
        REQUIRED_MODULES_KEY = /RequiredModules\s*=\s*@\(/i

        sig { params(file: Dependabot::DependencyFile).void }
        def initialize(file:)
          @file = file
          # Block comments (`<# ... #>`) are blanked out - not removed - so
          # every absolute offset below still lines up with `@file.content`,
          # but text like `#Requires -Modules` or `RequiredModules = @(`
          # written inside a comment can no longer match as a declaration.
          @content = T.let(blank_block_comments(T.must(file.content)), String)
        end

        sig { returns(T::Array[Occurrence]) }
        def locate
          case File.extname(@file.name).downcase
          when ".psd1"
            locate_required_modules
          when ".ps1", ".psm1"
            locate_requires_directives
          else
            []
          end
        end

        private

        # Replaces each `<# ... #>` block comment with equal-length
        # whitespace (newlines preserved), so every absolute offset used
        # elsewhere in this class still lines up with the original file
        # content, but comment text can no longer match REQUIRES_MODULES_LINE
        # or REQUIRED_MODULES_KEY.
        sig { params(content: String).returns(String) }
        def blank_block_comments(content)
          content.gsub(/<#.*?#>/m) { |match| match.gsub(/[^\n]/, " ") }
        end

        sig { returns(T::Array[Occurrence]) }
        def locate_requires_directives
          @content.to_enum(:scan, REQUIRES_MODULES_LINE).flat_map do
            match = T.must(Regexp.last_match)
            modules_text = T.must(match[:modules])
            entries(modules_text, T.must(match.begin(:modules)), declaration_type: :requires_directive)
          end
        end

        sig { returns(T::Array[Occurrence]) }
        def locate_required_modules
          match = REQUIRED_MODULES_KEY.match(@content)
          return [] unless match

          body_range = balanced_paren_range(@content, match.end(0) - 1)
          return [] unless body_range

          body_start, body_end = body_range
          entries(@content[body_start...body_end].to_s, body_start, declaration_type: :required_modules)
        end

        # Given content and the index of an opening `(`, returns the
        # [start, end) offsets of the substring between it and its matching
        # closing `)`, respecting quotes and nested braces/parens so that
        # nested `@{...}` hashtable entries don't prematurely close the
        # array. Mirrors Psd1ManifestParser#extract_balanced, but returns
        # offsets instead of the substring itself.
        sig { params(content: String, open_index: Integer).returns(T.nilable([Integer, Integer])) }
        def balanced_paren_range(content, open_index)
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
              return [start_index, index] if depth.zero?
            end
          end

          nil
        end

        # Splits `text` into its top-level comma-separated entries (ignoring
        # commas nested inside quotes or `@{...}`/`@(...)` literals), parses
        # each one, and returns an Occurrence for every entry the parser can
        # resolve to a module declaration. `base_offset` is `text`'s
        # absolute start offset within the file, used to translate the
        # relative spans found here into absolute file offsets.
        sig do
          params(text: String, base_offset: Integer, declaration_type: Symbol).returns(T::Array[Occurrence])
        end
        def entries(text, base_offset, declaration_type:)
          entry_spans(text).filter_map do |entry_start, entry_end|
            raw = text[entry_start...entry_end].to_s
            declaration = FileParser::ModuleSpecificationParser.parse(raw, declaration_type: declaration_type)
            next unless declaration

            Occurrence.new(
              name: declaration.name,
              style: T.cast(declaration.metadata[:style], Symbol),
              version_key: T.cast(declaration.metadata[:version_key], T.nilable(String)),
              start_index: base_offset + entry_start,
              end_index: base_offset + entry_end
            )
          end
        end

        # Splits `text` on top-level commas (depth/quote aware, matching
        # ModuleSpecificationParser.split_on) and returns the trimmed
        # [start, end) span of each resulting entry.
        sig { params(text: String).returns(T::Array[[Integer, Integer]]) }
        def entry_spans(text)
          spans = []
          segment_start = 0
          depth = 0
          quote = T.let(nil, T.nilable(String))

          text.each_char.with_index do |char, index|
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
            when ","
              if depth.zero?
                spans << [segment_start, index]
                segment_start = index + 1
              end
            end
          end
          spans << [segment_start, text.length]

          spans.filter_map { |entry_start, entry_end| trim_span(text, entry_start, entry_end) }
        end

        sig { params(text: String, start_index: Integer, end_index: Integer).returns(T.nilable([Integer, Integer])) }
        def trim_span(text, start_index, end_index)
          segment = T.must(text[start_index...end_index])
          leading = T.must(segment[/\A\s*/]).length
          trailing = T.must(segment[/\s*\z/]).length
          trimmed_start = start_index + leading
          trimmed_end = end_index - trailing

          return nil if trimmed_start >= trimmed_end

          [trimmed_start, trimmed_end]
        end
      end
    end
  end
end
