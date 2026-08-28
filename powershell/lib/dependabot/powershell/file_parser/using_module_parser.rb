# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/powershell/file_parser"
require "dependabot/powershell/file_parser/module_specification_parser"
require "dependabot/powershell/content_masker"

module Dependabot
  module Powershell
    class FileParser < Dependabot::FileParsers::Base
      # Parses native `using module` statements from PowerShell scripts and
      # exposes their source spans for the file updater.
      class UsingModuleParser
        extend T::Sig

        class Statement < T::Struct
          const :text, String
          const :start_index, Integer
          const :end_index, Integer
        end

        USING_MODULE_LINE = /^[ \t]*using[ \t]+module[ \t]+/i

        sig { params(file: Dependabot::DependencyFile).void }
        def initialize(file:)
          @file = file
        end

        sig { returns(T::Array[ModuleDeclaration]) }
        def parse
          content = ContentMasker.mask(T.must(@file.content))

          self.class.statements(content).filter_map do |statement|
            ModuleSpecificationParser.parse(statement.text, declaration_type: :using_module)
          end
        end

        sig { params(content: String).returns(T::Array[Statement]) }
        def self.statements(content)
          statements = []
          search_from = 0

          while (match = USING_MODULE_LINE.match(content, search_from))
            statement = statement_at(content, match.end(0))
            if statement
              statements << statement
              search_from = statement.end_index
            else
              search_from = match.end(0)
            end
          end

          statements
        end

        sig { params(content: String, value_start: Integer).returns(T.nilable(Statement)) }
        def self.statement_at(content, value_start)
          return hashtable_statement_at(content, value_start) if content[value_start, 2] == "@{"

          line_end = content.index("\n", value_start) || content.length
          text = T.must(content[value_start...line_end]).strip
          text = text.delete_suffix(";").rstrip
          return if text.empty?

          start_index = value_start
          start_index += 1 while start_index < line_end && T.must(content[start_index]).match?(/[ \t]/)

          Statement.new(
            text: text,
            start_index: start_index,
            end_index: start_index + text.length
          )
        end
        private_class_method :statement_at

        sig { params(content: String, value_start: Integer).returns(T.nilable(Statement)) }
        def self.hashtable_statement_at(content, value_start)
          end_index = balanced_hashtable_end(content, value_start + 1)
          return unless end_index

          Statement.new(
            text: T.must(content[value_start...end_index]),
            start_index: value_start,
            end_index: end_index
          )
        end
        private_class_method :hashtable_statement_at

        sig { params(content: String, open_brace_index: Integer).returns(T.nilable(Integer)) }
        def self.balanced_hashtable_end(content, open_brace_index)
          depth = 0
          quote = T.let(nil, T.nilable(String))
          index = open_brace_index

          while index < content.length
            char = T.must(content[index])

            if quote
              if quote == "\"" && char == "`" && index + 1 < content.length
                index += 2
                next
              end

              if char == quote && content[index + 1] == quote
                index += 2
                next
              end

              quote = nil if char == quote
              index += 1
              next
            end

            case char
            when "'", "\""
              quote = char
            when "{"
              depth += 1
            when "}"
              depth -= 1
              return index + 1 if depth.zero?
            end

            index += 1
          end

          nil
        end
        private_class_method :balanced_hashtable_end
      end
    end
  end
end
