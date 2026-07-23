# typed: strict
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

        REQUIRED_MODULES_KEY = /RequiredModules\s*=\s*@\(/i

        sig { params(file: Dependabot::DependencyFile).void }
        def initialize(file:)
          @file = file
        end

        sig { returns(T::Array[ModuleDeclaration]) }
        def parse
          body = required_modules_body
          return [] unless body

          ModuleSpecificationParser
            .split_entries(body)
            .filter_map { |entry| ModuleSpecificationParser.parse(entry, declaration_type: :required_modules) }
        end

        private

        sig { returns(T.nilable(String)) }
        def required_modules_body
          content = T.must(@file.content)
          match = REQUIRED_MODULES_KEY.match(content)
          return nil unless match

          # `match.end(0) - 1` is the index of the `(` that opens the
          # `RequiredModules` array literal.
          extract_balanced(content, match.end(0) - 1)
        end

        # Given content and the index of an opening `(` character, returns the
        # substring between it and its matching closing `)`, respecting
        # quoted strings and nested braces/parens so that nested `@{...}`
        # hashtable entries don't prematurely close the array.
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
