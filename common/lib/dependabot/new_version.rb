# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/version"

module Dependabot
  class NewVersion < ::Dependabot::Version
    extend T::Sig
    extend T::Helpers

    NULL_VALUES = T.let(%w(0 final ga).freeze, T::Array[String])
    PREFIXED_TOKEN_HIERARCHY = T.let({
      "." => { qualifier: 1, number: 4 },
      "-" => { qualifier: 2, number: 3 },
      "+" => { qualifier: 3, number: 2 }
    }.freeze, T::Hash[String, T::Hash[Symbol, Integer]])
    NAMED_QUALIFIERS_HIERARCHY = T.let({
      "a" => 1, "alpha"     => 1,
      "b" => 2, "beta"      => 2,
      "m" => 3, "milestone" => 3,
      "rc" => 4, "cr" => 4, "pr" => 4, "pre" => 4,
      "snapshot" => 5, "dev" => 5,
      "ga" => 6, "" => 6, "final" => 6,
      "sp" => 7
    }.freeze, T::Hash[String, Integer])
    VERSION_PATTERN =
      "[0-9a-zA-Z]+" \
      '(?>\.[0-9a-zA-Z]*)*' \
      '([_\-\+][0-9A-Za-z_-]*(\.[0-9A-Za-z_-]*)*)?'
    ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

    abstract!

    VersionParameter = T.type_alias { T.nilable(T.any(String, Integer, Gem::Version)) }

    sig { override.overridable.params(version: VersionParameter, version_string: T.nilable(String)).void }
    def initialize(version, version_string = nil)
      @version_string = T.let(version_string || version.to_s, String)
      super(version)
    end

    sig { override.overridable.params(version: VersionParameter).returns(Dependabot::Version) }
    def self.new(version)
      T.cast(super, Dependabot::NewVersion)
      super
    end

    # Opt-in to Rubygems 4 behavior
    sig { override.overridable.params(version: VersionParameter).returns(T::Boolean) }
    def self.correct?(version)
      return false if version.nil?

      version.to_s.match?(ANCHORED_VERSION_PATTERN)
    end

    sig { override.overridable.returns(String) }
    def to_semver
      @version_string
    end

    sig { override.overridable.returns(String) }
    def inspect
      "#<#{self.class} #{@version_string}>"
    end

    sig { override.overridable.returns(String) }
    def to_s
      @version_string
    end

    sig { override.overridable.returns(T::Boolean) }
    def prerelease?
      tokens.any? do |token|
        next true if token == "eap"
        next false unless NAMED_QUALIFIERS_HIERARCHY[T.must(token)]

        T.must(NAMED_QUALIFIERS_HIERARCHY[T.must(token)]) < 6
      end
    end

    # rubocop:disable  Metrics/AbcSize
    sig { params(other: T.any(String, Integer, Gem::Version)).returns(Integer) }
    def <=>(other)
      version = stringify_version(@version_string)
      version = fill_tokens(version)
      version = trim_version(version)

      other_version = stringify_version(other)
      other_version = fill_tokens(other_version)
      other_version = trim_version(other_version)

      version, other_version = convert_dates(version, other_version)

      prefixed_tokens = split_into_prefixed_tokens(T.must(version))
      other_prefixed_tokens = split_into_prefixed_tokens(T.must(other_version))

      prefixed_tokens, other_prefixed_tokens =
        pad_for_comparison(prefixed_tokens, other_prefixed_tokens)

      T.must(prefixed_tokens).count.times.each do |index|
        prefix = T.must(T.must(prefixed_tokens)[index])[0]
        token = T.must(T.must(prefixed_tokens)[index])[1..-1] || ""
        other_prefix = T.must(T.must(other_prefixed_tokens)[index])[0]
        other_token = T.must(T.must(other_prefixed_tokens)[index])[1..-1] || ""
        comp = compare_prefixed_token(
          prefix: prefix.to_s,
          token: token,
          other_prefix: other_prefix.to_s,
          other_token: other_token
        )
        return T.must(comp) unless T.must(comp).zero?
      end

      0
    end
    # rubocop:enable  Metrics/AbcSize

    private

    sig { returns(T::Array[T.nilable(String)]) }
    def tokens
      version = @version_string.to_s.downcase
      version = fill_tokens(version)
      version = trim_version(version)
      split_into_prefixed_tokens(version).map { |t| t[1..-1] }
    end

    sig { params(version: VersionParameter).returns(String) }
    def stringify_version(version)
      version = version.to_s.downcase

      # Not technically correct, but pragmatic
      version.gsub(/^v(?=\d)/, "")
    end

    sig { params(version: String).returns(String) }
    def fill_tokens(version)
      # Add separators when transitioning from digits to characters
      version = version.gsub(/(\d)([A-Za-z])/, '\1-\2')
      version = version.gsub(/([A-Za-z])(\d)/, '\1-\2')

      # Replace empty tokens with 0
      version = version.gsub(/([\.\-])([\.\-])/, '\10\2')
      version = version.gsub(/^([\.\-])/, '0\1')
      version.gsub(/([\.\-])$/, '\10')
    end

    sig { params(version: String).returns(String) }
    def trim_version(version)
      version.split("-").filter_map do |v|
        parts = T.let(v.split("."), T.nilable(T::Array[String]))
        parts = T.must(parts)[0..-2] while NULL_VALUES.include?(T.must(parts).last)
        T.must(parts).join(".")
      end.reject(&:empty?).join("-")
    end

    sig { params(version: String, other_version: String).returns(T::Array[String]) }
    def convert_dates(version, other_version)
      default = [version, other_version]
      return default unless version.match?(/^\d{4}-?\d{2}-?\d{2}$/)
      return default unless other_version.match?(/^\d{4}-?\d{2}-?\d{2}$/)

      [version.delete("-"), other_version.delete("-")]
    end

    sig { params(version: String).returns(T::Array[String]) }
    def split_into_prefixed_tokens(version)
      ".#{version}".split(/(?=[\-\.\+])/)
    end

    sig do
      params(prefixed_tokens: T::Array[String],
             other_prefixed_tokens: T::Array[String]).returns(T::Array[T::Array[String]])
    end
    def pad_for_comparison(prefixed_tokens, other_prefixed_tokens)
      prefixed_tokens = prefixed_tokens.dup
      other_prefixed_tokens = other_prefixed_tokens.dup

      longest = [prefixed_tokens, other_prefixed_tokens].max_by(&:count)
      shortest = [prefixed_tokens, other_prefixed_tokens].min_by(&:count)

      T.must(longest).count.times do |index|
        next unless T.must(shortest)[index].nil?

        segment = T.must(T.must(longest)[index])

        T.must(shortest)[index] = segment.start_with?(".") ? ".0" : "-"
      end

      [prefixed_tokens, other_prefixed_tokens]
    end

    sig { params(prefix: String, token: String, other_prefix: String, other_token: String).returns(T.nilable(Integer)) }
    def compare_prefixed_token(prefix:, token:, other_prefix:, other_token:)
      token_type = token.match?(/^\d+$/) ? :number : :qualifier
      other_token_type = other_token.match?(/^\d+$/) ? :number : :qualifier

      hierarchy = PREFIXED_TOKEN_HIERARCHY.fetch(prefix).fetch(token_type)
      other_hierarchy =
        PREFIXED_TOKEN_HIERARCHY.fetch(other_prefix).fetch(other_token_type)

      hierarchy_comparison = hierarchy <=> other_hierarchy
      return hierarchy_comparison unless hierarchy_comparison.zero?

      compare_token(token: token, other_token: other_token)
    end

    sig { params(token: String, other_token: String).returns(T.nilable(Integer)) }
    def compare_token(token:, other_token:)
      if (token_hierarchy = NAMED_QUALIFIERS_HIERARCHY[token])
        return -1 unless NAMED_QUALIFIERS_HIERARCHY[other_token]

        return token_hierarchy <=> NAMED_QUALIFIERS_HIERARCHY.fetch(other_token)
      end

      return 1 if NAMED_QUALIFIERS_HIERARCHY[other_token]

      if token.match?(/\A\d+\z/) && other_token.match?(/\A\d+\z/)
        token = token.to_i
        other_token = other_token.to_i
        return token <=> other_token
      end

      token <=> other_token
    end
  end
end
