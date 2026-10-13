# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/bun/file_updater"

module Dependabot
  module Bun
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Locates object members in JSON source text, so they can be edited in
      # place without reformatting the document.
      class JsonObjectMembers
        extend T::Sig

        # Maps each member of the JSON object opening at `start` whose value is
        # an object to the range of that value in `content`.
        sig { params(content: String, start: Integer).returns(T::Hash[String, T::Range[Integer]]) }
        def self.find(content, start)
          new.scan(content, start)
        end

        sig { void }
        def initialize
          @members = T.let({}, T::Hash[String, T::Range[Integer]])
          @depth = T.let(0, Integer)
          @key = T.let(nil, T.nilable(String))
          @value_start = T.let(nil, T.nilable(Integer))
          @string = T.let(nil, T.nilable(String))
          @last_string = T.let(nil, T.nilable(String))
          @escaped = T.let(false, T::Boolean)
        end

        sig { params(content: String, start: Integer).returns(T::Hash[String, T::Range[Integer]]) }
        def scan(content, start)
          T.must(content[start..]).each_char.with_index(start) do |char, index|
            if @string
              read_string(@string, char)
            else
              read_structure(char, index)
              break if @depth.zero?
            end
          end

          @members
        end

        private

        sig { params(string: String, char: String).void }
        def read_string(string, char)
          if @escaped
            @escaped = false
          elsif char == "\\"
            @escaped = true
          elsif char == "\""
            value = T.cast(JSON.parse("\"#{string}\""), String)
            @last_string = value
            @string = nil
            return
          end

          string << char
        end

        sig { params(char: String, index: Integer).void }
        def read_structure(char, index)
          case char
          when "\"" then @string = +""
          when ":" then @key = @last_string if @depth == 1
          when "," then @key = nil if @depth == 1
          when "{", "[" then enter(char, index)
          when "}", "]" then leave(index)
          end
        end

        sig { params(char: String, index: Integer).void }
        def enter(char, index)
          @value_start = index if @depth == 1 && char == "{" && @key
          @depth += 1
        end

        sig { params(index: Integer).void }
        def leave(index)
          @depth -= 1
          key = @key
          value_start = @value_start
          return unless @depth == 1 && key && value_start

          @members[key] = value_start..index
          @value_start = nil
        end
      end
    end
  end
end
