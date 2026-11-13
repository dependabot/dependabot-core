# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/manifest_sets/invalid_catalog"

module Dependabot
  module ManifestSets
    # Checks that a filename regex stays within the subset of syntax that Ruby's Onigmo engine and Go's
    # RE2-based `regexp` package interpret identically, then compiles it for Ruby. See README.md for the
    # grammar. Anything outside the subset is rejected rather than translated.
    class PortableRegex
      extend T::Sig

      MAX_BYTES = 1024
      MAX_REPEAT = 1000
      PREFIX = "\\A"
      SUFFIX = "\\z"
      # Characters that may be escaped to stand for themselves.
      ESCAPABLE_LITERALS = T.let(".^$|?*+()[]{}\\/-".chars.freeze, T::Array[String])
      # Control-character escapes; both engines map these to the same code points.
      CONTROL_ESCAPES = %w(t n v f r).freeze
      QUANTIFIERS = %w(* + ?).freeze
      BOUNDED_REPEAT = /\A\{(\d{1,4})(,(\d{1,4})?)?\}/

      sig { params(rule_id: String, source: String).returns(Regexp) }
      def self.compile(rule_id, source)
        new(rule_id, source).compile
      end

      sig { params(rule_id: String, source: String).void }
      def initialize(rule_id, source)
        @rule_id = rule_id
        @source = source
        @pos = T.let(0, Integer)
        @group_depth = T.let(0, Integer)
        @case_insensitive = T.let(false, T::Boolean)
        # True when the previous token can be repeated (an atom or a closed group).
        @repeatable = T.let(false, T::Boolean)
      end

      sig { returns(Regexp) }
      def compile
        validate
        Regexp.new(@source)
      rescue RegexpError => e
        reject("invalid_regex", e.message)
      end

      private

      sig { void }
      def validate
        reject("regex_too_long", "exceeds #{MAX_BYTES} bytes") if @source.bytesize > MAX_BYTES
        reject("non_portable_regex", "must be valid UTF-8") unless @source.valid_encoding?
        unless @source.start_with?(PREFIX) && @source.end_with?(SUFFIX) && @source.length > PREFIX.length + 1
          reject("missing_anchor", "must start with \\A and end with \\z")
        end

        body = @source[PREFIX.length...(@source.length - SUFFIX.length)].to_s
        # An odd run of backslashes before the final \z means the anchor is itself escaped.
        trailing = body[/\\*\z/].to_s.length
        reject("missing_anchor", "the final \\z is escaped") if trailing.odd?

        scan(body)
        reject("non_portable_regex", "unbalanced group") unless @group_depth.zero?
        return unless @case_insensitive && !@source.ascii_only?

        reject("non_portable_regex", "patterns using (?i: must be ASCII-only")
      end

      sig { params(body: String).void }
      def scan(body)
        chars = body.chars
        @pos = 0
        while @pos < chars.length
          char = T.must(chars[@pos])
          case char
          when "\\" then scan_escape(chars)
          when "[" then scan_class(chars)
          when "(" then scan_group_open(chars)
          when ")" then scan_group_close
          when "|" then scan_alternation
          when "*", "+", "?" then scan_quantifier(chars)
          when "{" then scan_bounded_repeat(chars)
          when "^", "$" then reject("non_portable_regex", "only \\A and \\z anchors are allowed")
          when "}", "]" then reject("non_portable_regex", "unescaped #{char}")
          else
            atom
          end
        end
      end

      sig { params(chars: T::Array[String]).void }
      def scan_escape(chars)
        escaped = chars[@pos + 1]
        reject("non_portable_regex", "dangling escape") if escaped.nil?
        unless ESCAPABLE_LITERALS.include?(escaped) || CONTROL_ESCAPES.include?(escaped)
          reject("non_portable_regex", "unsupported escape \\#{escaped}")
        end
        @pos += 2
        @repeatable = true
      end

      sig { params(chars: T::Array[String]).void }
      def scan_class(chars)
        @pos += 1
        @pos += 1 if chars[@pos] == "^"
        reject("non_portable_regex", "character class may not start with ]") if chars[@pos] == "]"

        members = 0
        loop do
          char = chars[@pos]
          reject("non_portable_regex", "unterminated character class") if char.nil?
          break if char == "]"

          case char
          when "\\"
            scan_escape(chars)
            next members += 1
          when "["
            reject("non_portable_regex", "nested classes and POSIX classes are not allowed")
          when "&"
            reject("non_portable_regex", "class intersection is not allowed") if chars[@pos + 1] == "&"
          end
          @pos += 1
          members += 1
        end
        reject("non_portable_regex", "empty character class") if members.zero?
        @pos += 1
        @repeatable = true
      end

      sig { params(chars: T::Array[String]).void }
      def scan_group_open(chars)
        if chars[@pos + 1] == "?"
          case chars[@pos + 2]
          when ":" then @pos += 3
          when "i"
            reject("non_portable_regex", "only the scoped (?i: flag group is allowed") unless chars[@pos + 3] == ":"
            @case_insensitive = true
            @pos += 4
          else
            reject("non_portable_regex", "only (...), (?:...) and (?i:...) groups are allowed")
          end
        else
          @pos += 1
        end
        @group_depth += 1
        @repeatable = false
      end

      sig { void }
      def scan_group_close
        reject("non_portable_regex", "unbalanced group") if @group_depth.zero?
        @group_depth -= 1
        @pos += 1
        @repeatable = true
      end

      sig { void }
      def scan_alternation
        reject("non_portable_regex", "top-level alternation escapes the anchors") if @group_depth.zero?
        @pos += 1
        @repeatable = false
      end

      sig { params(chars: T::Array[String]).void }
      def scan_quantifier(chars)
        reject("non_portable_regex", "quantifier has nothing to repeat") unless @repeatable
        @pos += 1
        follow_quantifier(chars)
      end

      sig { params(chars: T::Array[String]).void }
      def scan_bounded_repeat(chars)
        match = BOUNDED_REPEAT.match(T.must(chars[@pos..]).join)
        reject("non_portable_regex", "malformed {n,m} repetition") if match.nil?
        reject("non_portable_regex", "quantifier has nothing to repeat") unless @repeatable

        min = Integer(T.must(match[1]), 10)
        max = match[3] ? Integer(T.must(match[3]), 10) : nil
        if min > MAX_REPEAT || (max && max > MAX_REPEAT)
          reject("non_portable_regex", "repetition count exceeds #{MAX_REPEAT}")
        end
        reject("non_portable_regex", "repetition {n,m} requires n <= m") if max && max < min

        @pos += T.must(match[0]).length
        follow_quantifier(chars)
      end

      sig { params(chars: T::Array[String]).void }
      def follow_quantifier(chars)
        nxt = chars[@pos]
        if nxt && (QUANTIFIERS.include?(nxt) || nxt == "{")
          reject("non_portable_regex", "lazy, possessive and stacked quantifiers are not allowed")
        end
        @repeatable = false
      end

      sig { void }
      def atom
        @pos += 1
        @repeatable = true
      end

      sig { params(code: String, message: String).returns(T.noreturn) }
      def reject(code, message)
        raise InvalidCatalog.new(code, "rule #{@rule_id.inspect}: #{message}")
      end
    end
  end
end
