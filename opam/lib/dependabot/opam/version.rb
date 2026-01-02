# typed: strict
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Opam
    # OCaml opam uses Debian-style version ordering
    # See: https://opam.ocaml.org/doc/Manual.html#Version-ordering
    #
    # Version ordering follows these rules:
    # - Versions are split into alternating non-digit/digit sequences
    # - Sequences are compared lexicographically
    # - Non-digit components: letters < non-letters, with ASCII ordering for non-letters
    # - The ~ character sorts before the end of sequence (e.g., 1.0~beta < 1.0)
    # - Useful for pre-releases: 1.0~beta < 1.0 < 1.0.1
    #
    # Example ordering: ~~, ~, ~beta2, ~beta10, 0.1, 1.0~beta, 1.0, 1.0-test, 1.0.1, dev
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        version = version.to_s.strip
        return false if version.empty?
        return false if version.start_with?(".")
        return false if version.end_with?(".")

        # Opam versions can contain letters, digits, dots, tildes, hyphens, and plus signs
        version.match?(/^[a-zA-Z0-9.~+_-]+$/)
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        super
      end

      sig { override.returns(String) }
      def to_semver
        # Convert opam version to semver-compatible format
        # Replace ~ with - for pre-releases (1.0~beta -> 1.0-beta)
        version_string.tr("~", "-")
      end

      sig { params(other: Dependabot::Version).returns(Integer) }
      def <=>(other)
        return 0 if version_string == other.to_s

        # Use Debian-style version comparison
        compare_debian_versions(version_string, other.to_s)
      end

      private

      sig { returns(String) }
      attr_reader :version_string

      sig { params(ver1: String, ver2: String).returns(Integer) }
      def compare_debian_versions(ver1, ver2)
        # Split versions into alternating non-digit/digit sequences
        parts1 = split_version(ver1)
        parts2 = split_version(ver2)

        # Compare each part
        [parts1.length, parts2.length].max.times do |i|
          part1 = parts1[i] || ""
          part2 = parts2[i] || ""

          # Handle ~ specially - it sorts before empty string
          return -1 if part1 == "~" && part2 != "~"
          return 1 if part2 == "~" && part1 != "~"

          cmp = compare_parts(part1, part2)
          return cmp unless cmp.zero?
        end

        0
      end

      sig { params(version: String).returns(T::Array[String]) }
      def split_version(version)
        parts = []
        current = ""
        is_digit = T.let(nil, T.nilable(T::Boolean))

        version.each_char do |char|
          char_is_digit = char.match?(/\d/)

          if is_digit.nil?
            is_digit = char_is_digit
            current = char
          elsif is_digit == char_is_digit
            current += char
          else
            parts << current
            current = char
            is_digit = char_is_digit
          end
        end

        parts << current unless current.empty?
        parts
      end

      sig { params(part1: String, part2: String).returns(Integer) }
      def compare_parts(part1, part2)
        return 0 if part1 == part2

        tilde_result = compare_tilde_prefix(part1, part2)
        return tilde_result unless tilde_result.nil?

        part1, part2 = strip_tilde_prefix(part1, part2)

        # Check if parts are numeric
        return part1.to_i <=> part2.to_i if numeric?(part1) && numeric?(part2)

        compare_non_numeric_parts(part1, part2)
      end

      sig { params(part1: String, part2: String).returns(T.nilable(Integer)) }
      def compare_tilde_prefix(part1, part2)
        # Debian rule: ~ sorts before everything, even empty string
        return -1 if part1.start_with?("~") && !part2.start_with?("~")
        return 1 if !part1.start_with?("~") && part2.start_with?("~")

        nil
      end

      sig { params(part1: String, part2: String).returns([String, String]) }
      def strip_tilde_prefix(part1, part2)
        # If both start with ~, compare the rest
        if part1.start_with?("~") && part2.start_with?("~")
          [T.must(part1[1..]), T.must(part2[1..])]
        else
          [part1, part2]
        end
      end

      sig { params(part: String).returns(T::Boolean) }
      def numeric?(part)
        part.match?(/^\d+$/)
      end

      sig { params(part1: String, part2: String).returns(Integer) }
      def compare_non_numeric_parts(part1, part2)
        # Non-digit comparison: letters < non-letters
        part1.each_char.with_index do |char1, i|
          char2 = part2[i]
          return 1 if char2.nil? # part1 is longer

          result = compare_characters(char1, char2)
          return result unless result.zero?
        end

        part2.length > part1.length ? -1 : 0
      end

      sig { params(char1: String, char2: String).returns(Integer) }
      def compare_characters(char1, char2)
        char1_letter = char1.match?(/[a-zA-Z]/)
        char2_letter = char2.match?(/[a-zA-Z]/)

        return -1 if char1_letter && !char2_letter
        return 1 if !char1_letter && char2_letter

        T.must(char1 <=> char2)
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("opam", Dependabot::Opam::Version)
