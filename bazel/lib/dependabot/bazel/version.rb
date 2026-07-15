# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"
require "dependabot/dependency_file"

# Bazel pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.

module Dependabot
  module Bazel
    class Version < Dependabot::Version
      extend T::Sig

      # Wrapper CLIs that Bazelisk installs through its fork syntax ("<org>/<version>").
      # Their entries name the wrapper's own version, not a Bazel version, so
      # they must never be mistaken for a Bazel fork target.
      KNOWN_WRAPPER_ORGS = %w(buildbuddy-io).freeze

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        super(normalize_bazel_version(version.to_s))
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        @bcr_suffix = T.let(parse_bcr_suffix(@version_string), T.nilable(Integer))

        super(Dependabot::Bazel::Version.normalize_bazel_version(@version_string))
      end

      # Extracts the Bazel version from .bazelversion content: the first entry left by
      # `bazel_lines`, the same target `bazelisk_target_from_file` returns. For a fork target
      # (<fork>/<version>, like myorg/8.0.0) the part after the slash is returned. Targets
      # Bazelisk can't parse (more than one slash, or an empty fork or version) are rejected.
      # Only for .bazelversion content — plain version strings go through `correct?`/`new`.
      sig { params(version_string: VersionParameter).returns(String) }
      def self.extract_bazel_version(version_string)
        return "" if version_string.nil?

        target_line = bazel_lines(version_string.to_s).first
        return "" unless target_line

        # A negative limit keeps empty segments, so "8.0.0/" and "/8.0.0" are rejected too.
        segments = target_line.split("/", -1)
        return "" if segments.length > 2 || segments.any?(&:empty?)

        segments.last.to_s
      end

      # The target Bazelisk should run: the first entry left by `bazel_lines`. Fork targets
      # (myorg/8.0.0) are kept whole so Bazelisk fetches the fork rather than upstream Bazel.
      # Returns nil when nothing remains (empty or wrapper-only files).
      sig { params(file: T.nilable(Dependabot::DependencyFile)).returns(T.nilable(String)) }
      def self.bazelisk_target_from_file(file)
        content = file&.content
        return nil unless content

        bazel_lines(content).first
      end

      # The usable entries of .bazelversion content, in order. Bazelisk itself only reads the
      # first line. A wrapper such as BuildBuddy is listed there; it then drops its own leading
      # entries and runs the next one as Bazel
      # (https://www.buildbuddy.io/docs/cli/#installing-for-a-project). Dropping wrapper entries
      # here makes the first remaining entry the Bazel that actually runs. Blank and comment
      # lines are skipped too, which is more lenient than Bazelisk.
      sig { params(content: String).returns(T::Array[String]) }
      def self.bazel_lines(content)
        content.lines.map(&:strip)
               .reject { |l| l.empty? || l.start_with?("#") }
               .reject { |l| wrapper_line?(l) }
      end
      private_class_method :bazel_lines

      # GitHub org names are case-insensitive, so match wrapper entries case-insensitively.
      sig { params(line: String).returns(T::Boolean) }
      def self.wrapper_line?(line)
        org = line.split("/").first.to_s
        KNOWN_WRAPPER_ORGS.any? { |known| known.casecmp?(org) }
      end
      private_class_method :wrapper_line?

      # Strips .bcr.N suffix and v prefix from a version string to yield a Gem::Version-compatible string.
      sig { params(version_string: String).returns(String) }
      def self.normalize_bazel_version(version_string)
        version_string.sub(/\.bcr\.\d+$/, "").sub(/^v/i, "")
      end

      # Helper to cleanly extract and normalize a Bazel version directly from a DependencyFile
      # (`.bazelversion`). Returns nil when no parseable semantic version can be determined —
      # including Bazelisk-relative values like "latest" or "last_green" — so callers apply
      # their own fallbacks rather than crashing on a non-semver string.
      sig { params(file: T.nilable(Dependabot::DependencyFile)).returns(T.nilable(String)) }
      def self.version_from_file(file)
        content = file&.content
        return nil unless content

        extracted = extract_bazel_version(content)
        return nil if extracted.empty?

        normalized = normalize_bazel_version(extracted)
        return nil unless correct?(normalized)

        normalized
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { returns(T.nilable(Integer)) }
      attr_reader :bcr_suffix

      sig { override.params(other: BasicObject).returns(T.nilable(Integer)) }
      def <=>(other)
        other_bazel = convert_to_bazel_version(other)
        return nil unless other_bazel

        base_comparison = super(other_bazel)
        return base_comparison unless base_comparison&.zero?

        compare_bcr_suffixes(@bcr_suffix, other_bazel.bcr_suffix)
      end

      private

      sig { params(version_string: String).returns(T.nilable(Integer)) }
      def parse_bcr_suffix(version_string)
        match = version_string.match(/\.bcr\.(\d+)$/)
        match ? T.must(match[1]).to_i : nil
      end

      sig { params(other: BasicObject).returns(T.nilable(Dependabot::Bazel::Version)) }
      def convert_to_bazel_version(other)
        case other
        when Dependabot::Bazel::Version
          other
        when Gem::Version
          T.cast(Dependabot::Bazel::Version.new(other.to_s), Dependabot::Bazel::Version)
        when String
          T.cast(Dependabot::Bazel::Version.new(other), Dependabot::Bazel::Version)
        when Dependabot::Version
          T.cast(Dependabot::Bazel::Version.new(other.to_s), Dependabot::Bazel::Version)
        end
      end

      sig { params(ours: T.nilable(Integer), theirs: T.nilable(Integer)).returns(Integer) }
      def compare_bcr_suffixes(ours, theirs)
        return ours <=> theirs if ours && theirs

        return 1 if ours
        return -1 if theirs

        0
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("bazel", Dependabot::Bazel::Version)
