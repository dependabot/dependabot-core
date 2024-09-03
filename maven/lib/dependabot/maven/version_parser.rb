# typed: ignore
# frozen_string_literal: true

require "sorbet-runtime"
require "strscan"

# See https://maven.apache.org/pom.html#Version_Order_Specification for details
#
module Dependabot
  module Maven
    TokenBucket = Struct.new(:tokens, :addition) do
      def to_a
        return tokens if addition.nil?

        tokens.clone.append(addition.to_a)
      end

      def <=>(other)
        cmp = compare_tokens(tokens, other.tokens)
        return cmp unless cmp.zero?

        compare_additions(addition, other.addition)
      end

      def compare_tokens(a, b) # rubocop:disable Naming/MethodParameterName
        max_idx = [a.size, b.size].max - 1
        (0..max_idx).each do |idx|
          cmp = compare_token_pair(a[idx], b[idx])
          return cmp unless cmp.zero?
        end
        0
      end

      def compare_token_pair(a = 0, b = 0) # rubocop:disable Metrics/PerceivedComplexity
        a ||= 0
        b ||= 0

        if a.is_a?(Integer) && b.is_a?(String)
          return a <= 0 ? -1 : 1
        end

        if a.is_a?(String) && b.is_a?(Integer)
          return b <= 0 ? 1 : -1
        end

        if a == Dependabot::Maven::VersionParser::SP && b.is_a?(String) && b != Dependabot::Maven::VersionParser::SP
          return -1
        end

        if b == Dependabot::Maven::VersionParser::SP && a.is_a?(String) && a != Dependabot::Maven::VersionParser::SP
          return 1
        end

        a <=> b # a and b are both ints or strings
      end

      def compare_additions(first, second)
        return 0 if first.nil? && second.nil?

        (first || empty_addition) <=> (second || empty_addition)
      end

      def empty_addition
        TokenBucket.new([])
      end
    end

    class VersionParser
      extend T::Sig
      extend T::Helpers
      include Comparable

      ALPHA = -5
      BETA = -4
      MILESTONE = -3
      RC = -2
      SNAPSHOT = -1
      SP = "sp"

      def self.parse(version_string)
        new(version_string).parse
      end

      sig { returns(String) }
      attr_reader :version_string

      sig { params(version_string: String).void }
      def initialize(version_string)
        @version_string = version_string
      end

      def parse
        @scanner = StringScanner.new(version_string.downcase)
        @token_bucket = TokenBucket.new([])
        @result = @token_bucket
        parse_version(false)

        raise ArgumentError, "Malformed version string #{version_string}" if @result.to_a.empty?

        @result
      end

      private

      # sig { returns(String) }
      attr_reader :scanner

      def parse_addition(token = nil)
        @token_bucket.addition = TokenBucket.new([token].compact)
        @token_bucket = @token_bucket.addition

        scanner.skip(/-+/)
        parse_version(true)
      end

      def parse_version(number_begins_partition) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        # skip leading v if any
        scanner.skip(/v/)

        until scanner.eos?
          if (s = scanner.scan(/\d+/))
            if number_begins_partition
              parse_addition(s.to_i)
            else
              @token_bucket.tokens << s.to_i
            end

          elsif (s = scanner.match?(/a\d+/))
            # aN is equivalent to alpha-N
            scanner.skip("a")
            parse_addition(ALPHA)

          elsif (s = scanner.match?(/b\d+/))
            # bN is equivalent to beta-N
            scanner.skip("b")
            parse_addition(BETA)

          elsif (s = scanner.match?(/m\d+/))
            # mN is equivalent to milestone-N
            scanner.skip("m")
            parse_addition(MILESTONE)

          elsif (s = scanner.scan(/(alpha|beta|milestone|rc|cr|sp|ga|final|release|snapshot)[a-z]+/))
            # process "alpha" and others as normal lexical tokens if they're followed by a letter
            parse_addition(s)

          elsif (s = scanner.scan("alpha"))
            # handle alphaN, alpha-X, alpha.X, or ending alpha
            parse_addition(ALPHA)

          elsif (s = scanner.scan("beta"))
            parse_addition(BETA)
          elsif (s = scanner.scan("milestone"))
            parse_addition(MILESTONE)

          elsif (s = scanner.scan(/(rc|cr)/))
            parse_addition(RC)

          elsif (s = scanner.scan("snapshot"))
            parse_addition(SNAPSHOT)

          elsif (s = scanner.scan(/ga|final|release/))
            parse_addition

          elsif (s = scanner.scan("sp"))
            parse_addition(SP)

          # `+` is parsed as an addition as stated in maven version spec
          elsif (s = scanner.scan(/[a-z_+]+/))
            parse_addition(s)

          elsif (s = scanner.scan("."))
            number_begins_partition = false

          elsif (s = scanner.scan("-"))
            number_begins_partition = true

          else
            raise ArgumentError, scanner.rest
          end
        end
      end
    end
  end
end
