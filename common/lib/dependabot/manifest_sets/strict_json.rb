# typed: strict
# frozen_string_literal: true

require "json"
require "strscan"
require "sorbet-runtime"
require "dependabot/manifest_sets/invalid_catalog"

module Dependabot
  module ManifestSets
    # Validates that a document is strict RFC 8259 JSON before it is decoded. Ruby's JSON parser accepts
    # some extensions (such as comments) and silently keeps the last of duplicated object keys, which a
    # strict consumer in another language would treat differently.
    class StrictJson
      extend T::Sig

      # Containers may be nested at most this deep; the catalog itself needs five levels.
      MAX_NESTING = 32
      WHITESPACE = /[ \t\n\r]*/
      STRING_TOKEN = %r{"(?:[^"\\\x00-\x1F]|\\["\\/bfnrt]|\\u[0-9a-fA-F]{4})*"}
      NUMBER_TOKEN = /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/
      LITERAL_TOKEN = /true|false|null/

      sig { params(text: String).returns(T.anything) }
      def self.parse(text)
        new(text).parse
      end

      sig { params(text: String).void }
      def initialize(text)
        @text = text
        @scanner = T.let(StringScanner.new(text), StringScanner)
      end

      sig { returns(T.anything) }
      def parse
        unless @text.encoding == Encoding::UTF_8 && @text.valid_encoding?
          raise InvalidCatalog.new("invalid_json", "document is not valid UTF-8")
        end

        skip_whitespace
        parse_value(0)
        skip_whitespace
        fail_at("unexpected trailing content") unless @scanner.eos?

        JSON.parse(@text, create_additions: false, allow_nan: false, max_nesting: MAX_NESTING)
      rescue JSON::ParserError => e
        raise InvalidCatalog.new("invalid_json", e.message)
      end

      private

      sig { params(depth: Integer).void }
      def parse_value(depth)
        case @scanner.peek(1)
        when "{" then parse_object(depth + 1)
        when "[" then parse_array(depth + 1)
        when "\"" then scan_string
        else
          fail_at("unexpected token") unless @scanner.skip(NUMBER_TOKEN) || @scanner.skip(LITERAL_TOKEN)
        end
      end

      sig { params(depth: Integer).void }
      def parse_object(depth)
        fail_at("maximum nesting depth exceeded") if depth > MAX_NESTING
        @scanner.getch
        skip_whitespace
        return if @scanner.skip("}")

        keys = T.let({}, T::Hash[String, TrueClass])
        loop do
          key = scan_string
          raise InvalidCatalog.new("duplicate_key", "duplicate object key #{key.inspect}") if keys.key?(key)

          keys[key] = true
          skip_whitespace
          fail_at("expected ':'") unless @scanner.skip(":")
          skip_whitespace
          parse_value(depth)
          skip_whitespace
          break if @scanner.skip("}")

          fail_at("expected ',' or '}'") unless @scanner.skip(",")
          skip_whitespace
        end
      end

      sig { params(depth: Integer).void }
      def parse_array(depth)
        fail_at("maximum nesting depth exceeded") if depth > MAX_NESTING
        @scanner.getch
        skip_whitespace
        return if @scanner.skip("]")

        loop do
          parse_value(depth)
          skip_whitespace
          break if @scanner.skip("]")

          fail_at("expected ',' or ']'") unless @scanner.skip(",")
          skip_whitespace
        end
      end

      sig { returns(String) }
      def scan_string
        token = @scanner.scan(STRING_TOKEN)
        fail_at("expected string") unless token

        T.cast(JSON.parse(token), String)
      end

      sig { void }
      def skip_whitespace
        @scanner.skip(WHITESPACE)
      end

      sig { params(message: String).returns(T.noreturn) }
      def fail_at(message)
        raise InvalidCatalog.new("invalid_json", "#{message} at byte #{@scanner.pos}")
      end
    end
  end
end
