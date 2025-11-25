# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Conda
    # Conda version handling based on conda's version specification
    # See: https://docs.conda.io/projects/conda/en/stable/user-guide/concepts/pkg-specs.html
    #
    # Version format: [epoch!]version[+local]
    #
    # Components:
    # - Epoch (optional): Integer prefix with ! separator (e.g., "1!2.0")
    # - Version: Main version identifier with segments separated by . or _
    # - Local version (optional): Build metadata with + prefix (e.g., "1.0+abc.7")
    #
    # Special handling:
    # - "dev" pre-releases sort before all other pre-releases
    # - "post" releases sort after the main version
    # - Underscores are normalized to dots
    # - Case-insensitive string comparison
    # - Fillvalue 0 insertion for missing segments
    # - Integer < String in mixed-type segment comparison (numeric before pre-release)
    class Version < Dependabot::Version
      extend T::Sig

      VERSION_PATTERN = /\A[a-z0-9_.!+\-]+\z/i

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil? || version.to_s.empty?

        version.to_s.match?(VERSION_PATTERN)
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Conda::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Conda::Version)
      end

      sig { returns(Integer) }
      attr_reader :epoch

      sig { returns(T::Array[T.any(Integer, String)]) }
      attr_reader :version_parts

      sig { returns(T.nilable(T::Array[T.any(Integer, String)])) }
      attr_reader :local_parts

      VersionParts = T.let(Struct.new(:epoch, :main, :local, keyword_init: true), T.untyped)
      private_constant :VersionParts

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)

        raise ArgumentError, "Malformed version string #{version}" unless self.class.correct?(version)

        # Validate no empty segments
        validate_version!(@version_string)

        # Parse epoch, main version, and local version
        parts = parse_epoch_and_local(@version_string)

        @epoch = T.let(parts.epoch.to_i, Integer)
        @version_parts = T.let(parse_components(parts.main), T::Array[T.any(Integer, String)])
        @local_parts = T.let(
          parts.local ? parse_components(parts.local) : nil,
          T.nilable(T::Array[T.any(Integer, String)])
        )

        super
      end

      sig { override.params(other: T.untyped).returns(T.nilable(Integer)) }
      def <=>(other)
        return nil unless other.is_a?(Dependabot::Conda::Version)

        # Step 1: Compare epochs (numerically)
        epoch_comparison = @epoch <=> other.epoch
        return epoch_comparison unless epoch_comparison.zero?

        # Step 2: Compare version parts (segment by segment with fillvalue)
        version_comparison = compare_parts(@version_parts, other.version_parts)
        return version_comparison unless version_comparison.zero?

        # Step 3: Compare local parts (if present)
        compare_local_parts(@local_parts, other.local_parts)
      end

      private

      # Validates version string for malformed segments
      sig { params(version_str: String).void }
      def validate_version!(version_str)
        main_version = parse_epoch_and_local(version_str).main

        # Check for empty segments (consecutive dots, leading/trailing dots)
        return unless main_version.include?("..") || main_version.match?(/^\./) || main_version.match?(/\.$/)

        raise ArgumentError, "Empty version segments not allowed in #{version_str}"
      end

      # Parses epoch and local version from version string
      # Returns VersionParts struct with epoch, main, and local fields
      sig { params(version_str: String).returns(T.untyped) }
      def parse_epoch_and_local(version_str)
        # Split on '!' for epoch
        parts = version_str.split("!", 2)
        if parts.length == 2
          epoch_str = parts[0]
          remainder = T.must(parts[1])
        else
          epoch_str = "0"
          remainder = parts[0]
        end

        # Split on '+' for local version
        parts = T.must(remainder).split("+", 2)
        main_version = parts[0]
        local_version = parts[1]

        VersionParts.new(epoch: epoch_str, main: T.must(main_version), local: local_version)
      end

      # Parses version components into normalized segments
      # Normalizes underscores to dots, handles special strings (dev, post)
      # Splits alphanumeric segments like "a1" into ["a", 1]
      sig { params(version_str: String).returns(T::Array[T.any(Integer, String)]) }
      def parse_components(version_str)
        # Normalize underscores to dots
        normalized = version_str.tr("_", ".")

        # Split on dots and dashes
        raw_segments = normalized.split(/[.\-]/)

        # Process each segment
        segments = T.let([], T::Array[T.any(Integer, String)])
        raw_segments.each do |segment|
          next if segment.empty?

          process_segment(segment, segments)
        end

        segments
      end

      # Process a single version segment and add results to segments array
      sig do
        params(
          segment: String,
          segments: T::Array[T.any(Integer, String)]
        ).void
      end
      def process_segment(segment, segments)
        # Key insight: Pre-release markers are only recognized when EMBEDDED in
        # numeric segments (e.g., "0a1" in "1.0a1"), NOT when they appear as
        # separate dot-delimited components (e.g., "rc1" in "2.rc1").
        lower_seg = segment.downcase
        has_embedded_prerelease = embedded_prerelease?(lower_seg)

        subsegments = T.cast(segment.scan(/\d+|[a-z]+/i), T::Array[String])

        if has_embedded_prerelease
          process_prerelease_subsegments(subsegments, segments)
        else
          process_normal_subsegments(subsegments, segments)
        end
      end

      # Check if segment contains an embedded pre-release marker
      sig { params(lower_seg: String).returns(T::Boolean) }
      def embedded_prerelease?(lower_seg)
        # Embedded: digits + a/b/rc + required digits (e.g., "0a1", "10b2", "2rc1")
        lower_seg.match?(/^\d+(a|alpha|b|beta|rc|c)\d+$/) ||
          # Embedded: digits + dev/post + optional digits (e.g., "0dev", "10post1")
          lower_seg.match?(/^\d+(dev|post)\d*$/)
      end

      # Process subsegments that contain pre-release markers
      sig do
        params(
          subsegments: T::Array[String],
          segments: T::Array[T.any(Integer, String)]
        ).void
      end
      def process_prerelease_subsegments(subsegments, segments)
        subsegments.each do |subseg|
          lower_subseg = subseg.downcase
          segments << if lower_subseg.match?(/^(dev|a|alpha|b|beta|rc|c|post)$/)
                        normalize_prerelease_segment(subseg)
                      elsif subseg.match?(/^\d+$/)
                        subseg.to_i
                      else
                        subseg.downcase
                      end
        end
      end

      # Process normal subsegments (no pre-release markers)
      sig do
        params(
          subsegments: T::Array[String],
          segments: T::Array[T.any(Integer, String)]
        ).void
      end
      def process_normal_subsegments(subsegments, segments)
        subsegments.each do |subseg|
          segments << if subseg.match?(/^\d+$/)
                        subseg.to_i
                      else
                        subseg.downcase
                      end
        end
      end

      # Normalizes a pre-release or post-release segment
      # Only called for confirmed pre-release/post-release patterns
      sig { params(segment: String).returns(T.any(Integer, String)) }
      def normalize_prerelease_segment(segment)
        lower_segment = segment.downcase

        # Pre-releases: use negative integers to sort before 0
        return -4 if dev_prerelease?(lower_segment)
        return -3 if alpha_prerelease?(lower_segment)
        return -2 if beta_prerelease?(lower_segment)
        return -1 if rc_prerelease?(lower_segment)

        # Post-releases: use ~ prefix to sort after everything
        return "~#{lower_segment}" if post_release?(lower_segment)

        lower_segment
      end

      # Check if segment is dev pre-release
      sig { params(lower_segment: String).returns(T::Boolean) }
      def dev_prerelease?(lower_segment)
        lower_segment == "dev" || lower_segment.match?(/^dev\d/)
      end

      # Check if segment is alpha pre-release
      sig { params(lower_segment: String).returns(T::Boolean) }
      def alpha_prerelease?(lower_segment)
        lower_segment == "a" || lower_segment == "alpha" || lower_segment.match?(/^(a|alpha)\d/)
      end

      # Check if segment is beta pre-release
      sig { params(lower_segment: String).returns(T::Boolean) }
      def beta_prerelease?(lower_segment)
        lower_segment == "b" || lower_segment == "beta" || lower_segment.match?(/^(b|beta)\d/)
      end

      # Check if segment is rc pre-release
      sig { params(lower_segment: String).returns(T::Boolean) }
      def rc_prerelease?(lower_segment)
        lower_segment == "rc" || lower_segment == "c" || lower_segment.match?(/^(rc|c)\d/)
      end

      # Check if segment is post-release
      sig { params(lower_segment: String).returns(T::Boolean) }
      def post_release?(lower_segment)
        lower_segment == "post" || lower_segment.start_with?("post")
      end

      # Compares two arrays of version parts with fillvalue insertion
      sig do
        params(
          parts1: T::Array[T.any(Integer, String)],
          parts2: T::Array[T.any(Integer, String)]
        ).returns(Integer)
      end
      def compare_parts(parts1, parts2)
        max_length = [parts1.length, parts2.length].max

        max_length.times do |i|
          # Insert fillvalue 0 for missing segments
          seg1 = parts1[i] || 0
          seg2 = parts2[i] || 0

          result = compare_single_segment(seg1, seg2)
          return result unless result.zero?
        end

        0 # All segments equal
      end

      # Compares two individual segments
      # Rules:
      # - Both integers: numeric comparison
      # - Both strings: case-insensitive lexicographic comparison
      # - Mixed types: Integer < String (numeric versions sort before pre-releases)
      sig { params(seg1: T.any(Integer, String), seg2: T.any(Integer, String)).returns(Integer) }
      def compare_single_segment(seg1, seg2)
        # Both integers: numeric comparison
        return seg1 <=> seg2 if seg1.is_a?(Integer) && seg2.is_a?(Integer)

        # Both strings: case-insensitive lexicographic
        # (already normalized to lowercase in parse_components)
        return T.must(seg1 <=> seg2) if seg1.is_a?(String) && seg2.is_a?(String)

        # Mixed types: Integer < String
        # This means 1.0.0 (with fillvalue 0) < 1.0.0a (with "a")
        seg1.is_a?(Integer) ? -1 : 1
      end

      # Compares local version parts
      # - nil local version sorts before any local version
      # - Both nil: equal
      # - Otherwise compare using same rules as version parts
      sig do
        params(
          local1: T.nilable(T::Array[T.any(Integer, String)]),
          local2: T.nilable(T::Array[T.any(Integer, String)])
        ).returns(Integer)
      end
      def compare_local_parts(local1, local2)
        # Both nil: equal
        return 0 if local1.nil? && local2.nil?

        # One nil: nil sorts before any local version
        return -1 if local1.nil?
        return 1 if local2.nil?

        # Both present: compare using same rules as version parts
        compare_parts(local1, local2)
      end
    end
  end
end

Dependabot::Utils.register_version_class("conda", Dependabot::Conda::Version)
