# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/maven_osv/version_parser"

# See https://maven.apache.org/pom.html#Version_Order_Specification for details
#
module Dependabot
  module MavenOSV
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

      sig do
        params(
          first: T::Array[T.any(String, Integer)],
          second: T::Array[T.any(String, Integer)]
        ).returns(T.nilable(Integer))
      end
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

        if first == Dependabot::MavenOSV::VersionParser::SP &&
           second.is_a?(String) && second != Dependabot::MavenOSV::VersionParser::SP
          return -1
        end

        if second == Dependabot::MavenOSV::VersionParser::SP &&
           first.is_a?(String) && first != Dependabot::MavenOSV::VersionParser::SP
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
  end
end
