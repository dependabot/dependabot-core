# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "strscan"

# See https://maven.apache.org/pom.html#Version_Order_Specification for details
#
module Dependabot
  module Maven
    class TokenBucket < T::Struct
      extend T::Sig
      extend T::Helpers
      include Comparable

      prop :tokens, T::Array[T.untyped]
      prop :addition, T.nilable(TokenBucket)

      sig { returns(T::Array[T.untyped]) }
      def to_a
        return tokens if addition.nil?

        tokens.clone.append(addition.to_a)
      end

      sig { params(other: TokenBucket).returns(T.nilable(Integer)) }
      def <=>(other)
        cmp = compare_tokens(tokens, other.tokens)
        return cmp unless cmp&.zero?

        compare_additions(addition, other.addition)
      end

      sig { params(first: T::Array[Integer], second: T::Array[Integer]).returns(T.nilable(Integer)) }
      def compare_tokens(first, second)
        max_idx = [first.size, second.size].max - 1
        (0..max_idx).each do |idx|
          cmp = compare_token_pair(first[idx], second[idx])
          return cmp unless T.must(cmp).zero?
        end
        0
      end

      sig do
        params(
          first: T.nilable(T.any(String, Integer)),
          second: T.nilable(T.any(String, Integer))
        ).returns(T.nilable(Integer))
      end
      def compare_token_pair(first = 0, second = 0) # rubocop:disable Metrics/PerceivedComplexity,Metrics/CyclomaticComplexity
        first ||= 0
        second ||= 0

        if first.is_a?(Integer) && second.is_a?(String)
          return first <= 0 ? -1 : 1
        end

        if first.is_a?(String) && second.is_a?(Integer)
          return second <= 0 ? 1 : -1
        end

        if first == Dependabot::Maven::VersionParser::SP &&
           second.is_a?(String) && second != Dependabot::Maven::VersionParser::SP
          return -1
        end

        if second == Dependabot::Maven::VersionParser::SP &&
           first.is_a?(String) && first != Dependabot::Maven::VersionParser::SP
          return 1
        end

        if first.is_a?(Integer) && second.is_a?(Integer)
          first <=> second
        elsif first.is_a?(String) && second.is_a?(String)
          first <=> second
        end
      end

      sig do
        params(first: T.nilable(TokenBucket), second: T.nilable(TokenBucket)).returns(T.nilable(Integer))
      end
      def compare_additions(first, second)
        return 0 if first.nil? && second.nil?

        (first || empty_addition) <=> (second || empty_addition)
      end

      sig { returns(TokenBucket) }
      def empty_addition
        TokenBucket.new(tokens: [])
      end
    end

    class VersionParser
      extend T::Sig
      extend T::Helpers

      ALPHA = -5
      BETA = -4
      MILESTONE = -3
      RC = -2
      SNAPSHOT = -1
      SP = "sp"

      sig { params(version: T.nilable(String)).returns(TokenBucket) }
      def self.parse(version)
        raise ArgumentError, "Malformed version string #{version}" if version.nil?

        new(version).parse
      end

      sig { params(version: String).void }
      def initialize(version)
        @version = version
        @token_bucket = T.let(TokenBucket.new(tokens: []), T.nilable(TokenBucket))
        @parse_result = T.let(@token_bucket, T.nilable(TokenBucket))
        @scanner = T.let(StringScanner.new(version.downcase), StringScanner)
      end

      sig { returns(TokenBucket) }
      def parse
        parse_version(false)

        raise ArgumentError, "Malformed version string #{version}" if parse_result.to_a.empty?

        T.must(parse_result)
      end

      private

      sig { returns(StringScanner) }
      attr_reader :scanner

      sig { returns(String) }
      attr_reader :version

      sig { returns(T.nilable(TokenBucket)) }
      attr_reader :parse_result

      sig { params(token: T.nilable(T.any(String, Integer))).void }
      def parse_addition(token = nil)
        @token_bucket&.addition = TokenBucket.new(tokens: [token].compact)
        @token_bucket = @token_bucket&.addition

        scanner.skip(/-+/)
        parse_version(true)
      end

      sig { params(number_begins_partition: T.nilable(T::Boolean)).void }
      def parse_version(number_begins_partition) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        # skip leading v if any
        scanner.skip(/v/)

        until scanner.eos?
          if (s = scanner.scan(/\d+/))
            if number_begins_partition
              parse_addition(s.to_i)
            else
              T.must(@token_bucket).tokens << s.to_i
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
