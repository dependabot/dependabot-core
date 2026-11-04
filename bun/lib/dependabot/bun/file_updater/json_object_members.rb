# typed: strong
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
        def self.objects(content, start)
          new(content, start).objects
        end

        # Maps each member of the JSON object opening at `start` whose value is
        # a string to the range of that value, quotes included, in `content`.
        sig { params(content: String, start: Integer).returns(T::Hash[String, T::Range[Integer]]) }
        def self.strings(content, start)
          new(content, start).strings
        end

        sig { returns(T::Hash[String, T::Range[Integer]]) }
        attr_reader :objects

        sig { returns(T::Hash[String, T::Range[Integer]]) }
        attr_reader :strings

        sig { params(content: String, start: Integer).void }
        def initialize(content, start)
          @objects = T.let({}, T::Hash[String, T::Range[Integer]])
          @strings = T.let({}, T::Hash[String, T::Range[Integer]])
          @depth = T.let(0, Integer)
          @key = T.let(nil, T.nilable(String))
          @value_start = T.let(nil, T.nilable(Integer))
          @string = T.let(nil, T.nilable(String))
          @last_string = T.let(nil, T.nilable(String))
          @escaped = T.let(false, T::Boolean)
          scan(content, start)
        end

        private

        sig { params(content: String, start: Integer).void }
        def scan(content, start)
          T.must(content[start..]).each_char.with_index(start) do |char, index|
            if @string
              read_string(@string, char, index)
            else
              read_structure(char, index)
              break if @depth.zero?
            end
          end
        end

        sig { params(string: String, char: String, index: Integer).void }
        def read_string(string, char, index)
          if @escaped
            @escaped = false
          elsif char == "\\"
            @escaped = true
          elsif char == "\""
            close_string(string, index)
            return
          end

          string << char
        end

        sig { params(char: String, index: Integer).void }
        def read_structure(char, index)
          case char
          when "\"" then open_string(index)
          when ":" then @key = @last_string if @depth == 1
          when "," then @key = nil if @depth == 1
          when "{", "[" then enter(char, index)
          when "}", "]" then leave(index)
          end
        end

        sig { params(index: Integer).void }
        def open_string(index)
          @string = +""
          @value_start = index if @depth == 1 && @key
        end

        sig { params(string: String, index: Integer).void }
        def close_string(string, index)
          value = T.cast(JSON.parse("\"#{string}\""), String)
          @last_string = value
          @string = nil
          record(@strings, index) if @depth == 1
        end

        sig { params(char: String, index: Integer).void }
        def enter(char, index)
          @value_start = index if @depth == 1 && char == "{" && @key
          @depth += 1
        end

        sig { params(index: Integer).void }
        def leave(index)
          @depth -= 1
          record(@objects, index) if @depth == 1
        end

        sig { params(members: T::Hash[String, T::Range[Integer]], index: Integer).void }
        def record(members, index)
          key = @key
          value_start = @value_start
          return unless key && value_start

          members[key] = value_start..index
          @value_start = nil
        end
      end
    end
  end
end
