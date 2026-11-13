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
      # Bounds may not have leading zeros: Go treats {01} as literal text while Ruby treats it as a count.
      BOUNDED_REPEAT = /\A\{(0|[1-9]\d{0,3})(,(0|[1-9]\d{0,3})?)?\}/

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
        # True when the previous token can be repeated (an atom or a closed group).
        @repeatable = T.let(false, T::Boolean)
        # Go rejects nested {n,m} repetitions whose counts multiply past MAX_REPEAT. These track the largest
        # such product in the item being quantified, in finished items at the current group level, and in
        # the enclosing levels.
        @item_weight = T.let(nil, T.nilable(Integer))
        @level_weight = T.let(1, Integer)
        @outer_weights = T.let([], T::Array[Integer])
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
        start_item(1)
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
        start_item(1)
      end

      sig { params(chars: T::Array[String]).void }
      def scan_group_open(chars)
        if chars[@pos + 1] == "?"
          # Flags such as (?i: are excluded: they fold non-ASCII characters (U+212A matches k), so rules
          # spell out ASCII classes instead.
          reject("non_portable_regex", "only (...) and (?:...) groups are allowed") unless chars[@pos + 2] == ":"
          @pos += 3
        else
          @pos += 1
        end
        @group_depth += 1
        finish_item
        @outer_weights.push(@level_weight)
        @level_weight = 1
        @repeatable = false
      end

      sig { void }
      def scan_group_close
        reject("non_portable_regex", "unbalanced group") if @group_depth.zero?
        @group_depth -= 1
        @pos += 1
        finish_item
        group_weight = @level_weight
        @level_weight = T.must(@outer_weights.pop)
        start_item(group_weight)
      end

      sig { void }
      def scan_alternation
        reject("non_portable_regex", "top-level alternation escapes the anchors") if @group_depth.zero?
        @pos += 1
        finish_item
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

        min, max = repeat_bounds(match)
        if min > MAX_REPEAT || (max && max > MAX_REPEAT)
          reject("non_portable_regex", "repetition count exceeds #{MAX_REPEAT}")
        end
        reject("non_portable_regex", "repetition {n,m} requires n <= m") if max && max < min

        @item_weight = repeated_weight(min, max)
        @pos += T.must(match[0]).length
        follow_quantifier(chars)
      end

      # {n} repeats exactly n times; only {n,} is open-ended (a nil maximum).
      sig { params(match: MatchData).returns([Integer, T.nilable(Integer)]) }
      def repeat_bounds(match)
        min = Integer(T.must(match[1]), 10)
        return [min, min] if match[2].nil?

        [min, match[3] ? Integer(T.must(match[3]), 10) : nil]
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
        start_item(1)
      end

      sig { params(weight: Integer).void }
      def start_item(weight)
        finish_item
        @item_weight = weight
        @repeatable = true
      end

      sig { void }
      def finish_item
        @level_weight = [@level_weight, @item_weight].max if @item_weight
        @item_weight = nil
      end

      # Mirrors Go's regexp/syntax repeatIsValid: {0} hides what it repeats, an open {n,} counts as n, and
      # counts along any nesting path may not multiply past MAX_REPEAT.
      sig { params(min: Integer, max: T.nilable(Integer)).returns(Integer) }
      def repeated_weight(min, max)
        return 1 if max&.zero?

        weight = [max || min, 1].max * T.must(@item_weight)
        reject("non_portable_regex", "nested repetition counts exceed #{MAX_REPEAT}") if weight > MAX_REPEAT
        weight
      end

      sig { params(code: String, message: String).returns(T.noreturn) }
      def reject(code, message)
        raise InvalidCatalog.new(code, "rule #{@rule_id.inspect}: #{message}")
      end
    end
  end
end
