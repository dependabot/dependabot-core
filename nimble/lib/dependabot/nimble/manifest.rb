# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Nimble
    # Reads the dependencies a `.nimble` file declares. A package file is Nim code, but its
    # dependencies are plain calls:
    #
    #   requires "nim >= 2.0.0", "chronos >= 4.0.4"
    #   requires("bearssl")
    #   taskRequires "test", "unittest2 ~= 0.2"
    #
    # Each string is located by its offsets in the file, so a version can be changed in place
    # without disturbing anything around it.
    class Manifest
      extend T::Sig

      Entry = T.type_alias { Dependabot::Nimble::Manifest::Requires }

      # One string of a `requires` or `taskRequires` call.
      class Requires
        extend T::Sig

        sig { returns(String) }
        attr_reader :name

        sig { returns(String) }
        attr_reader :requirement

        sig { returns(T.nilable(String)) }
        attr_reader :task

        sig { returns(Integer) }
        attr_reader :requirement_start

        sig { returns(Integer) }
        attr_reader :requirement_end

        sig do
          params(
            name: String,
            requirement: String,
            task: T.nilable(String),
            requirement_start: Integer,
            requirement_end: Integer
          ).void
        end
        def initialize(name:, requirement:, task:, requirement_start:, requirement_end:)
          @name = name
          @requirement = requirement
          @task = task
          @requirement_start = requirement_start
          @requirement_end = requirement_end
        end
      end

      # The compiler: `requires "nim >= 2.0"` states which Nim the package supports, which is
      # not a dependency to keep current.
      LANGUAGE_PACKAGE = "nim"

      INLINE_SPACE = [" ", "\t"].freeze
      WHITESPACE = [" ", "\t", "\r", "\n"].freeze

      CALL = /^[ \t]*(?<call>requires|taskRequires)\b[ \t]*(?<paren>\()?[ \t]*/
      PACKAGE = /\A(?<lead>\s*)(?<name>[^\s<>=~^#&*"]+)(?<gap>\s*)(?<requirement>.*?)\s*\z/m

      sig { params(content: String).void }
      def initialize(content)
        @content = content
      end

      # The entries Dependabot tracks: packages of the index with a version or none, in file order.
      sig { returns(T::Array[Requires]) }
      def dependencies
        requires.reject { |entry| entry.name == LANGUAGE_PACKAGE || entry.requirement.start_with?("#") }
      end

      sig { returns(T::Array[Requires]) }
      def requires
        @requires ||= T.let(scan, T.nilable(T::Array[Requires]))
      end

      private

      sig { returns(T::Array[Requires]) }
      def scan
        entries = T.let([], T::Array[Requires])
        position = 0
        while (match = CALL.match(@content, position))
          position = match.end(0)
          literals = string_literals(position)
          position = literals.last&.last || position
          task = nil
          task = literals.shift&.first if match[:call] == "taskRequires"
          literals.each do |text, finish|
            entry = entry_for(text, finish, task)
            entries << entry if entry
          end
        end
        entries
      end

      # The string literals of one call: [content, offset of the closing quote], in order.
      sig { params(start: Integer).returns(T::Array[[String, Integer]]) }
      def string_literals(start)
        literals = T.let([], T::Array[[String, Integer]])
        position = start
        while @content[position] == '"' && @content[position, 3] != '"""'
          finish = closing_quote(position + 1)
          break unless finish

          literals << [T.must(@content[(position + 1)...finish]), finish]
          position = skip_inline_space(finish + 1)
          break unless @content[position] == ","

          position = skip_whitespace(position + 1)
        end
        literals
      end

      sig { params(from: Integer).returns(T.nilable(Integer)) }
      def closing_quote(from)
        index = from
        while index < @content.length
          case @content[index]
          when "\\" then index += 1
          when '"' then return index
          when "\n" then return nil
          end
          index += 1
        end
        nil
      end

      sig { params(index: Integer).returns(Integer) }
      def skip_inline_space(index)
        index += 1 while INLINE_SPACE.include?(@content[index])
        index
      end

      sig { params(index: Integer).returns(Integer) }
      def skip_whitespace(index)
        index += 1 while WHITESPACE.include?(@content[index])
        index
      end

      sig { params(text: String, finish: Integer, task: T.nilable(String)).returns(T.nilable(Requires)) }
      def entry_for(text, finish, task)
        match = PACKAGE.match(text)
        return unless match

        name = T.must(match[:name])
        # `https://github.com/a/b` and `a/b` name a repository, not a package of the index.
        return if name.include?("/") || name.include?(":") || name.include?("@")

        start = finish - text.length + match.begin(:requirement)
        Requires.new(
          name: name,
          requirement: T.must(match[:requirement]),
          task: task,
          requirement_start: start,
          requirement_end: start + T.must(match[:requirement]).length
        )
      end
    end
  end
end
