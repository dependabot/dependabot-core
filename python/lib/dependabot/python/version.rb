# typed: true
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

# Python versions can include a local version identifier, which Ruby can't
# parse. This class augments Gem::Version with local version identifier info.
# See https://www.python.org/dev/peps/pep-0440 for details.

module Dependabot
  module Python
    class Version < Dependabot::Version
      sig { returns(Integer) }
      attr_reader :epoch

      sig { returns(T::Array[String]) }
      attr_reader :release
      attr_reader :dev

      sig { returns(T.nilable(T::Array[T.any(String, Integer)])) }
      attr_reader :pre

      attr_reader :post
      attr_reader :local

      NEGATIVE_INFINITY = -10
      INFINITY = 10

      # See https://peps.python.org/pep-0440/#appendix-b-parsing-version-strings-with-regular-expressions
      VERSION_PATTERN = /
        v?
        (?:
          (?:(?<epoch>[0-9]+)!)?                          # epoch
          (?<release>[0-9]+(?:\.[0-9]+)*)                 # release
          (?<pre>                                         # prerelease
            [-_\.]?
            (?<pre_l>(a|b|c|rc|alpha|beta|pre|preview))
            [-_\.]?
            (?<pre_n>[0-9]+)?
          )?
          (?<post>                                        # post release
            (?:-(?<post_n1>[0-9]+))
            |
            (?:
                [-_\.]?
                (?<post_l>post|rev|r)
                [-_\.]?
                (?<post_n2>[0-9]+)?
            )
          )?
          (?<dev>                                          # dev release
            [-_\.]?
            (?<dev_l>dev)
            [-_\.]?
            (?<dev_n>[0-9]+)?
          )?
        )
        (?:\+(?<local>[a-z0-9]+(?:[-_\.][a-z0-9]+)*))?    # local version
      /ix

      ANCHORED_VERSION_PATTERN = /\A\s*#{VERSION_PATTERN}\s*\z/

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = version.to_s

        matches = ANCHORED_VERSION_PATTERN.match(@version_string.downcase)

        raise Dependabot::BadRequirementError unless matches

        @epoch = matches["epoch"].to_i
        @release = matches["release"]&.split(".")&.map(&:to_i) || []
        @pre = parse_letter_version(matches["pre_l"], matches["pre_n"])
        @post = parse_letter_version(matches["post_l"], matches["post_n1"] || matches["post_n2"])
        @dev = parse_letter_version(matches["dev_l"], matches["dev_n"])
        @local = parse_local_version(matches["local"])
      end

      # def initialize(version)
      #   @version_string = version.to_s
      #   version, @local_version = @version_string.split("+")
      #   version ||= ""
      #   version = version.gsub(/^v/, "")
      #   if version.include?("!")
      #     @epoch, version = version.split("!")
      #   else
      #     @epoch = "0"
      #   end
      #   version = normalise_prerelease(version)
      #   version, @post_release_version = version.split(/\.r(?=\d)/)
      #   version ||= ""
      #   @local_version = normalise_prerelease(@local_version) if @local_version
      #   super
      # end

      def to_s
        @version_string
      end

      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      sig { params(other: T.any(String, Dependabot::Python::Version)).returns(Integer) }
      def <=>(other)
        other = Dependabot::Python::Version.new(other.to_s) unless other.is_a?(Python::Version)

        epoch_comparison = epoch <=> other.epoch
        return epoch_comparison unless epoch_comparison.zero?

        release_comparison = release_version_comparison(other)
        return release_comparison unless release_comparison.zero?

        pre_comparison = pre_version_comparison(other)
        return pre_comparison unless pre_comparison.zero?

        post_comparison = post_cmp_key <=> other.post_cmp_key
        return post_comparison unless post_comparison.zero?

        local_version_comparison(other)
      end

      sig { params(other: Dependabot::Python::Version).returns(Integer) }
      def pre_version_comparison(other)
        key = pre_cmp_key
        other_key = other.pre_cmp_key

        if key.is_a?(Integer) && other_key.is_a?(Integer)
          key <=> other_key
        elsif key.is_a?(Array) && other_key.is_a?(Array)
          key <=> other_key
        elsif key.is_a?(Integer)
          key == NEGATIVE_INFINITY ? -1 : 1
        elsif other_key.is_a?(Integer)
          other_key == NEGATIVE_INFINITY ? 1 : -1
        end
      end

      sig { returns(T.any(Integer, T::Array[T.any(String, Integer)])) }
      def pre_cmp_key
        if pre.nil? && post.nil? && dev # sort 1.0.dev0 before 1.0a0
          NEGATIVE_INFINITY
        elsif pre.nil?
          INFINITY # versions without a pre-release should sort after those with one.
        else
          T.must(pre)
        end
      end

      private

      def local_cmp_key
        if local.nil?
          # Versions without a local segment should sort before those with one.
          NEGATIVE_INFINITY
        else
          # According to PEP440.
          # - Alphanumeric segments sort before numeric segments
          # - Alphanumeric segments sort lexicographically
          # - Numeric segments sort numerically
          # - Shorter versions sort before longer versions when the prefixes match exactly
          local.map do |token|
            if token.is_a?(Integer)
              [token, ""]
            else
              [NEGATIVE_INFINITY, token]
            end
          end
        end
      end

      def post_cmp_key
        # Versions without a post segment should sort before those with one.
        if post.nil?
          NEGATIVE_INFINITY
        else
          post
        end
      end

      def release_version_comparison(other)
        tokens, other_tokens = pad_for_comparison(release, other.release)

        tokens <=> other_tokens

        # tokens.zip(other_tokens).each do |token, other_token|
        #   result = token <=> other_token
        #   return result unless result.zero?
        # end

        # 0
      end

      def pad_for_comparison(tokens, other_tokens)
        tokens = tokens.dup
        other_tokens = other_tokens.dup

        longer = [tokens, other_tokens].max_by(&:count)
        shorter = [tokens, other_tokens].min_by(&:count)

        difference = longer.length - shorter.length

        difference.times { shorter << 0 }

        [tokens, other_tokens]
      end

      sig { params(local: T.nilable(String)).returns(T.nilable(T::Array[T.any(String, Integer)])) }
      def parse_local_version(local)
        return if local.nil?

        # Takes a string like abc.1.twelve and turns it into ["abc", 1, "twelve"]
        local.split(/[\._-]/).map { |s| /\d+/.match?(s) ? s.to_i : s }
      end

      sig do
        params(
          letter: T.nilable(String), number: T.nilable(String)
        ).returns(T.nilable(T::Array[T.any(String, Integer)]))
      end
      def parse_letter_version(letter = nil, number = nil)
        return if letter.nil? && number.nil?

        if letter
          # Implicit 0 for cases where prerelease has no numeral
          number ||= 0

          # Normalize alternate spellings
          if letter == "alpha"
            letter = "a"
          elsif letter == "beta"
            letter = "b"
          elsif letter in %w(c pre preview)
            letter = "rc"
          elsif letter in %w(rev r)
            letter = "post"
          end

          return letter, number.to_i
        end

        # Number but no letter i.e. implicit post release syntax (e.g. 1.0-1)
        letter = "post"

        [letter, number.to_i]
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("pip", Dependabot::Python::Version)
