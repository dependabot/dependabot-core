# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module Vcpkg
    # vcpkg has four version schemes and a `#<port-version>` suffix, and it refuses to compare
    # versions whose schemes are incomparable. This class mirrors `compare_any` in vcpkg-tool's
    # `src/vcpkg/versions.cpp`: a version's comparison class is inferred from its text, dates
    # compare with dates, dot-versions with dot-versions, and arbitrary strings only with
    # themselves.
    #
    # See https://learn.microsoft.com/vcpkg/users/versioning#version-schemes
    class Version < Dependabot::Version
      extend T::Sig

      # `version-date`: an ISO-8601 date with optional dot-separated disambiguators.
      DATE_PATTERN = /\d{4}-\d{2}-\d{2}(?:\.(?:0|[1-9]\d*))*/

      # `version` and `version-semver`: dot-separated numbers with optional semver pre-release
      # identifiers and build metadata.
      DOT_PATTERN = /
        (?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*))*
        (?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?
        (?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?
      /x

      # `version-string` accepts arbitrary text. `#` is reserved for the port version.
      STRING_PATTERN = /[^\s#]+/

      PORT_VERSION_PATTERN = /(?:\#(?:0|[1-9]\d*))?/

      VERSION_PATTERN = /#{STRING_PATTERN}#{PORT_VERSION_PATTERN}/

      # Requirement strings prefix a version with an operator, so the string scheme must not be
      # allowed to swallow one.
      REQUIREMENT_VERSION_PATTERN = /(?![=<>~!])#{VERSION_PATTERN}/

      ANCHORED_VERSION_PATTERN = /\A\s*#{VERSION_PATTERN}\s*\z/
      ANCHORED_DATE_PATTERN = /\A#{DATE_PATTERN}\z/
      ANCHORED_DOT_PATTERN = /\A#{DOT_PATTERN}\z/

      # A vcpkg version always contains a digit. Requiring one keeps git refs out: a registry
      # baseline's previous version is a ref such as `master`, and `MetadataFinders`, `Labeler` and
      # `UpdateCheckers::Base` all use `correct?` to tell a version from a ref. Treating `master` as
      # a `version-string` made `ReleaseFinder` compare release tags against it and discard them,
      # dropping the release notes from baseline pull requests.
      DIGIT_PATTERN = /[0-9]/

      # A handful of ancient ports use a bare commit SHA as a `version-string`, but so does every
      # vcpkg registry baseline. Treating those as versions would stop `UpdateCheckers::Base` from
      # recognizing a baseline as a git SHA, so this rejects them. Digit-only strings still count,
      # because they are valid relaxed versions.
      GIT_SHA_PATTERN = /\A(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\z/

      DATE_LENGTH = 10

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s.strip, String)
        raise ArgumentError, "Malformed version number string #{version}" unless self.class.correct?(@version_string)

        text, port_version = self.class.split_port_version(@version_string)
        @text = T.let(text, String)
        @port_version = T.let(port_version, Integer)
        @comparison_class = T.let(self.class.comparison_class_for(text), Symbol)

        @dot_parts = T.let(nil, T.nilable([T::Array[Integer], T::Array[String]]))
        @date_identifiers = T.let(nil, T.nilable(T::Array[Integer]))
        @natural_key = T.let(nil, T.nilable(T::Array[T::Array[T.any(Integer, String)]]))

        super(self.class.numeric_surrogate(text))
      end

      sig { returns(String) }
      attr_reader :text

      sig { returns(Integer) }
      attr_reader :port_version

      # One of `:dot`, `:date` or `:string`.
      sig { returns(Symbol) }
      attr_reader :comparison_class

      sig { override.params(version: VersionParameter).returns(Dependabot::Vcpkg::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Vcpkg::Version)
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return true if version.is_a?(Gem::Version)
        return false if version.nil?

        string = version.to_s.strip
        return false if string.empty?
        return false unless DIGIT_PATTERN.match?(string)
        return false if GIT_SHA_PATTERN.match?(string)

        ANCHORED_VERSION_PATTERN.match?(string)
      end

      sig { params(version_string: String).returns([String, Integer]) }
      def self.split_port_version(version_string)
        text, port_version = version_string.split("#", 2)
        [text.to_s, port_version.to_i]
      end

      sig { params(text: String).returns(Symbol) }
      def self.comparison_class_for(text)
        return :date if ANCHORED_DATE_PATTERN.match?(text)
        return :dot if ANCHORED_DOT_PATTERN.match?(text)

        :string
      end

      # A version's scheme is declared in the versions database, not implied by its text: vcpkg
      # publishes plenty of dotted values under `version-string`. Inference is only a fallback for
      # values that arrive without one, such as advisory version lists.
      SCHEME_CLASSES = T.let(
        {
          "version" => :dot,
          "version-semver" => :dot,
          "version-date" => :date,
          "version-string" => :string
        }.freeze,
        T::Hash[String, Symbol]
      )

      sig { params(scheme: T.nilable(String)).returns(T.nilable(Symbol)) }
      def self.comparison_class_for_scheme(scheme)
        scheme && SCHEME_CLASSES[scheme]
      end

      # Mirrors `compare_version_texts` in vcpkg-tool: dot versions compare with dot versions,
      # dates with dates, and arbitrary strings only with an identical string. A string-scheme
      # version is never comparable with a typed one, even when the text matches.
      sig do
        params(
          left: Vcpkg::Version,
          left_scheme: T.nilable(String),
          right: Vcpkg::Version,
          right_scheme: T.nilable(String)
        ).returns(T::Boolean)
      end
      def self.comparable?(left, left_scheme, right, right_scheme)
        left_class = comparison_class_for_scheme(left_scheme) || left.comparison_class
        right_class = comparison_class_for_scheme(right_scheme) || right.comparison_class

        return left.text == right.text if left_class == :string && right_class == :string
        return false if left_class == :string || right_class == :string

        left_class == right_class
      end

      # `Gem::Version` only accepts dot-separated alphanumerics, so string-scheme versions get a
      # numeric stand-in instead. This class overrides every comparison, so the stand-in only backs
      # the inherited `segments` and sort-key plumbing.
      sig { params(text: String).returns(String) }
      def self.numeric_surrogate(text)
        text[/\A\d+(?:\.\d+)*/] || "0"
      end

      sig { params(other: Object).returns(T.nilable(Vcpkg::Version)) }
      def self.coerce(other)
        return other if other.is_a?(Vcpkg::Version)
        return nil unless other.is_a?(String) || other.is_a?(Integer) || other.is_a?(Gem::Version)

        string = other.to_s
        correct?(string) ? new(string) : nil
      end

      # Semver pre-release ordering: numeric identifiers sort below non-numeric ones, numerics
      # compare numerically, and everything else compares as ASCII.
      sig { params(left: T::Array[String], right: T::Array[String]).returns(Integer) }
      def self.compare_identifiers(left, right)
        left.each_with_index do |identifier, index|
          other_identifier = right[index]
          return 1 if other_identifier.nil?

          comparison = compare_identifier(identifier, other_identifier)
          return comparison unless comparison.zero?
        end

        left.length <=> right.length
      end

      sig { params(left: String, right: String).returns(Integer) }
      def self.compare_identifier(left, right)
        left_numeric = left.match?(/\A\d+\z/)
        right_numeric = right.match?(/\A\d+\z/)

        return left.to_i <=> right.to_i if left_numeric && right_numeric
        return -1 if left_numeric
        return 1 if right_numeric

        T.must(left <=> right)
      end

      sig { returns(T::Boolean) }
      def dot? = comparison_class == :dot

      sig { returns(T::Boolean) }
      def date? = comparison_class == :date

      sig { returns(T::Boolean) }
      def string? = comparison_class == :string

      # vcpkg reports an error rather than an ordering when two versions have incomparable schemes.
      # `#<=>` still has to return a total order so release lists can be sorted, so callers that
      # need vcpkg's own answer ask this instead.
      sig { params(other: Vcpkg::Version).returns(T::Boolean) }
      def comparable_with?(other)
        return true if dot? && other.dot?
        return true if date? && other.date?

        string? && other.string? && text == other.text
      end

      sig { override.returns(String) }
      def to_s = @version_string

      sig { override.returns(String) }
      def to_semver = @version_string

      sig { returns(String) }
      def inspect = "#<#{self.class} #{@version_string.inspect}>"

      sig { returns(T::Boolean) }
      def prerelease? = dot? && dot_identifiers.any?

      sig { params(other: Object).returns(T::Boolean) }
      def eql?(other)
        other.is_a?(Vcpkg::Version) && text == other.text && port_version == other.port_version
      end

      sig { returns(Integer) }
      def hash = [text, port_version].hash

      sig { params(other: Object).returns(T.nilable(Integer)) }
      def <=>(other)
        other = self.class.coerce(other)
        return nil unless other

        comparison = compare_text(other)
        return comparison unless comparison.zero?

        port_version <=> other.port_version
      end

      protected

      # The numeric segments of a dot-version, e.g. `[1, 2, 3]` for `1.2.3-alpha+build`.
      sig { returns(T::Array[Integer]) }
      def dot_numbers = dot_parts.first

      # The semver pre-release identifiers of a dot-version, e.g. `["alpha", "1"]`.
      sig { returns(T::Array[String]) }
      def dot_identifiers = dot_parts.last

      sig { returns(String) }
      def date_part = text[0, DATE_LENGTH].to_s

      sig { returns(T::Array[Integer]) }
      def date_identifiers
        @date_identifiers ||= text[DATE_LENGTH..].to_s.split(".").reject(&:empty?).map(&:to_i)
      end

      sig { returns(T::Array[T::Array[T.any(Integer, String)]]) }
      def natural_key
        @natural_key ||= text.scan(/\d+|\D+/).map do |match|
          part = T.cast(match, String)
          part.match?(/\A\d+\z/) ? [0, part.to_i, ""] : [1, 0, part]
        end
      end

      private

      sig { returns([T::Array[Integer], T::Array[String]]) }
      def dot_parts
        @dot_parts ||= parse_dot_version
      end

      sig { params(other: Vcpkg::Version).returns(Integer) }
      def compare_text(other)
        return compare_dot(other) if dot? && other.dot?
        return compare_date(other) if date? && other.date?
        return 0 if text == other.text

        compare_naturally(other)
      end

      sig { params(other: Vcpkg::Version).returns(Integer) }
      def compare_dot(other)
        comparison = dot_numbers <=> other.dot_numbers
        return comparison unless comparison.nil? || comparison.zero?

        # An absent pre-release sorts above one that is present, e.g. `1.0.0` > `1.0.0-1`.
        return 0 if dot_identifiers.empty? && other.dot_identifiers.empty?
        return 1 if dot_identifiers.empty?
        return -1 if other.dot_identifiers.empty?

        self.class.compare_identifiers(dot_identifiers, other.dot_identifiers)
      end

      sig { params(other: Vcpkg::Version).returns(Integer) }
      def compare_date(other)
        comparison = date_part <=> other.date_part
        return comparison unless comparison.nil? || comparison.zero?

        (date_identifiers <=> other.date_identifiers) || 0
      end

      # vcpkg refuses to order these, but sorting a release list still has to terminate, so fall
      # back to a natural ordering of the raw text. Callers that need vcpkg's answer use
      # `#comparable_with?`.
      sig { params(other: Vcpkg::Version).returns(Integer) }
      def compare_naturally(other)
        comparison = natural_key <=> other.natural_key
        return comparison unless comparison.nil? || comparison.zero?

        (text <=> other.text) || 0
      end

      sig { returns([T::Array[Integer], T::Array[String]]) }
      def parse_dot_version
        return [[], []] unless dot?

        core, prerelease = T.must(text.split("+", 2).first).split("-", 2)
        [T.must(core).split(".").map(&:to_i), prerelease.to_s.split(".").reject(&:empty?)]
      end
    end
  end
end

Dependabot::Utils.register_version_class("vcpkg", Dependabot::Vcpkg::Version)
