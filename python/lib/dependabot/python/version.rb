# typed: true
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

# See https://packaging.python.org/en/latest/specifications/version-specifiers for spec details.

module Dependabot
  module Python
    class Version < Dependabot::Version
      sig { returns(Integer) }
      attr_reader :epoch

      sig { returns(T::Array[Integer]) }
      attr_reader :release_segment

      sig { returns(T.nilable(T::Array[T.any(String, Integer)])) }
      attr_reader :dev

      sig { returns(T.nilable(T::Array[T.any(String, Integer)])) }
      attr_reader :pre

      sig { returns(T.nilable(T::Array[T.any(String, Integer)])) }
      attr_reader :post

      sig { returns(T.nilable(T::Array[T.any(String, Integer)])) }
      attr_reader :local

      attr_reader :local_version
      attr_reader :post_release_version

      INFINITY = 1000
      NEGATIVE_INFINITY = -INFINITY

      # See https://peps.python.org/pep-0440/#appendix-b-parsing-version-strings-with-regular-expressions
      NEW_VERSION_PATTERN = /
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

      VERSION_PATTERN = 'v?([1-9][0-9]*!)?[0-9]+[0-9a-zA-Z]*(?>\.[0-9a-zA-Z]+)*' \
                        '(-[0-9A-Za-z]+(\.[0-9a-zA-Z]+)*)?' \
                        '(\+[0-9a-zA-Z]+(\.[0-9a-zA-Z]+)*)?'

      ANCHORED_VERSION_PATTERN = /\A\s*#{VERSION_PATTERN}\s*\z/

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        if Dependabot::Experiments.enabled?(:python_new_version)
          version.to_s.match?(/\A\s*#{NEW_VERSION_PATTERN}\s*\z/o)
        else
          version.to_s.match?(ANCHORED_VERSION_PATTERN)
        end
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version) # rubocop:disable Metrics/AbcSize,Metrics/PerceivedComplexity
        raise Dependabot::BadRequirementError, "Malformed version string - string is nil" if version.nil?

        @version_string = version.to_s

        raise Dependabot::BadRequirementError, "Malformed version string - string is empty" if @version_string.empty?

        matches = anchored_version_pattern.match(@version_string.downcase)

        unless matches
          raise Dependabot::BadRequirementError,
                "Malformed version string - #{@version_string} does not match regex"
        end

        if Dependabot::Experiments.enabled?(:python_new_version)
          @epoch = matches["epoch"].to_i
          @release_segment = matches["release"]&.split(".")&.map(&:to_i) || []
          @pre = parse_letter_version(matches["pre_l"], matches["pre_n"])
          @post = parse_letter_version(matches["post_l"], matches["post_n1"] || matches["post_n2"])
          @dev = parse_letter_version(matches["dev_l"], matches["dev_n"])
          @local = parse_local_version(matches["local"])
          super(matches["release"] || "")
        else
          version, @local_version = @version_string.split("+")
          version ||= ""
          version = version.gsub(/^v/, "")
          if version.include?("!")
            epoch, version = version.split("!")
            @epoch = epoch.to_i
          else
            @epoch = 0
          end
          version = normalise_prerelease(version)
          version, @post_release_version = version.split(/\.r(?=\d)/)
          version ||= ""
          @local_version = normalise_prerelease(@local_version) if @local_version
          super
        end
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Python::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Python::Version)
      end

      sig { returns(String) }
      def to_s
        @version_string
      end

      sig { returns(String) }
      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      sig { returns(T::Boolean) }
      def prerelease?
        return super unless Dependabot::Experiments.enabled?(:python_new_version)

        !!(pre || dev)
      end

      sig { returns(T.any(Gem::Version, Dependabot::Python::Version)) }
      def release
        return super unless Dependabot::Experiments.enabled?(:python_new_version)

        Dependabot::Python::Version.new(release_segment.join("."))
      end

      sig { params(other: VersionParameter).returns(Integer) }
      def <=>(other) # rubocop:disable Metrics/AbcSize,Metrics/PerceivedComplexity
        other = Dependabot::Python::Version.new(other.to_s) unless other.is_a?(Dependabot::Python::Version)
        other = T.cast(other, Dependabot::Python::Version)

        if Dependabot::Experiments.enabled?(:python_new_version)
          epoch_comparison = epoch <=> other.epoch
          return epoch_comparison unless epoch_comparison.zero?

          release_comparison = release_version_comparison(other)
          return release_comparison unless release_comparison.zero?

          pre_comparison = compare_keys(pre_cmp_key, other.pre_cmp_key)
          return pre_comparison unless pre_comparison.zero?

          post_comparison = compare_keys(post_cmp_key, other.post_cmp_key)
          return post_comparison unless post_comparison.zero?

          dev_comparison = compare_keys(dev_cmp_key, other.dev_cmp_key)
          return dev_comparison unless dev_comparison.zero?

          compare_keys(local_cmp_key, other.local_cmp_key)
        else
          epoch_comparison = epoch_comparison(other)
          return epoch_comparison unless epoch_comparison.zero?

          version_comparison = super
          return T.must(version_comparison) unless version_comparison&.zero?

          post_version_comparison = post_version_comparison(other)
          return post_version_comparison unless post_version_comparison.zero?

          local_version_comparison(other)
        end
      end

      sig do
        params(
          key: T.any(Integer, T::Array[T.any(String, Integer)]),
          other_key: T.any(Integer, T::Array[T.any(String, Integer)])
        ).returns(Integer)
      end
      def compare_keys(key, other_key)
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

      sig { returns(T.any(Integer, T::Array[T.any(String, Integer)])) }
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
          local&.map do |token|
            if token.is_a?(Integer)
              [token, ""]
            else
              [NEGATIVE_INFINITY, token]
            end
          end
        end
      end

      sig { returns(T.any(Integer, T::Array[T.any(String, Integer)])) }
      def post_cmp_key
        # Versions without a post segment should sort before those with one.
        return NEGATIVE_INFINITY if post.nil?

        T.must(post)
      end

      sig { returns(T.any(Integer, T::Array[T.any(String, Integer)])) }
      def dev_cmp_key
        # Versions without a dev segment should sort after those with one.
        return INFINITY if dev.nil?

        T.must(dev)
      end

      private

      sig { params(other: Dependabot::Python::Version).returns(Integer) }
      def release_version_comparison(other)
        tokens, other_tokens = pad_for_comparison(release_segment, other.release_segment)
        tokens <=> other_tokens
      end

      sig do
        params(
          tokens: T::Array[Integer],
          other_tokens: T::Array[Integer]
        ).returns(T::Array[T::Array[Integer]])
      end
      def pad_for_comparison(tokens, other_tokens)
        tokens = tokens.dup
        other_tokens = other_tokens.dup

        longer = [tokens, other_tokens].max_by(&:count)
        shorter = [tokens, other_tokens].min_by(&:count)

        difference = T.must(longer).length - T.must(shorter).length

        difference.times { T.must(shorter) << 0 }

        [tokens, other_tokens]
      end

      sig { params(local: T.nilable(String)).returns(T.nilable(T::Array[T.any(String, Integer)])) }
      def parse_local_version(local)
        return if local.nil?

        # Takes a string like abc.1.twelve and turns it into ["abc", 1, "twelve"]
        local.split(/[\._-]/).map { |s| /^\d+$/.match?(s) ? s.to_i : s }
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
          elsif %w(c pre preview).include? letter
            letter = "rc"
          elsif %w(rev r).include? letter
            letter = "post"
          end

          return letter, number.to_i
        end

        # Number but no letter i.e. implicit post release syntax (e.g. 1.0-1)
        letter = "post"

        [letter, number.to_i]
      end

      sig { returns(Regexp) }
      def anchored_version_pattern
        if Dependabot::Experiments.enabled?(:python_new_version)
          /\A\s*#{NEW_VERSION_PATTERN}\s*\z/o
        else
          ANCHORED_VERSION_PATTERN
        end
      end

      def epoch_comparison(other)
        epoch.to_i <=> other.epoch.to_i
      end

      def post_version_comparison(other)
        unless other.post_release_version
          return post_release_version.nil? ? 0 : 1
        end

        return -1 if post_release_version.nil?

        post_release_version.to_i <=> other.post_release_version.to_i
      end

      def local_version_comparison(other)
        # Local version comparison works differently in Python: `1.0.beta`
        # compares as greater than `1.0`. To accommodate, we make the
        # strings the same length before comparing.
        lhsegments = local_version.to_s.split(".").map(&:downcase)
        rhsegments = other.local_version.to_s.split(".").map(&:downcase)
        limit = [lhsegments.count, rhsegments.count].min

        lhs = ["1", *lhsegments.first(limit)].join(".")
        rhs = ["1", *rhsegments.first(limit)].join(".")

        local_comparison = Gem::Version.new(lhs) <=> Gem::Version.new(rhs)

        return local_comparison unless local_comparison&.zero?

        lhsegments.count <=> rhsegments.count
      end

      def normalise_prerelease(version)
        # Python has reserved words for release states, which are treated
        # as equal (e.g., preview, pre and rc).
        # Further, Python treats dashes as a separator between version
        # parts and treats the alphabetical characters in strings as the
        # start of a new version part (so 1.1a2 == 1.1.alpha.2).
        version
          .gsub("alpha", "a")
          .gsub("beta", "b")
          .gsub("preview", "c")
          .gsub("pre", "c")
          .gsub("post", "r")
          .gsub("rev", "r")
          .gsub(/([\d.\-_])rc([\d.\-_])?/, '\1c\2')
          .tr("-", ".")
          .gsub(/(\d)([a-z])/i, '\1.\2')
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("pip", Dependabot::Python::Version)
