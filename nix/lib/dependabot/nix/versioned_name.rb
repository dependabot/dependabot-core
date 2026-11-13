# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Nix
    # Parses a NixOS-style versioned name (e.g. "nixos-26.05", "nixpkgs-24.11-darwin")
    # into prefix, YY.MM version, and suffix, and compares names within a family.
    class VersionedName
      extend T::Sig

      # prefix + YY.MM version + optional suffix, e.g. "nixpkgs-26.05-darwin".
      VERSIONED_NAME_PATTERN =
        /\A(?<prefix>.+[.\-_])(?<version>\d{2}\.\d{2})(?<suffix>-[a-zA-Z0-9]+)?\z/

      sig { params(name: String).void }
      def initialize(name)
        @name = name
        @match = T.let(VERSIONED_NAME_PATTERN.match(name), T.nilable(MatchData))
      end

      sig { returns(String) }
      attr_reader :name

      sig { returns(T::Boolean) }
      def versioned?
        !@match.nil?
      end

      sig { returns(T.nilable(String)) }
      def prefix
        @match&.[](:prefix)
      end

      sig { returns(T.nilable(String)) }
      def suffix
        @match&.[](:suffix)
      end

      sig { returns(T.nilable(String)) }
      def version_string
        @match&.[](:version)
      end

      # YY.MM as a comparable [year, month], or nil.
      sig { returns(T.nilable(T::Array[Integer])) }
      def version
        version_str = version_string
        return unless version_str

        parse_version(version_str)
      end

      # Same prefix and suffix, so bumps stay within e.g. nixos-* (not nixos-*-small).
      sig { params(other: VersionedName).returns(T::Boolean) }
      def same_family?(other)
        versioned? && other.versioned? &&
          prefix == other.prefix && suffix == other.suffix
      end

      sig { params(other: VersionedName).returns(T::Boolean) }
      def newer_than?(other)
        this_version = version
        other_version = other.version
        return false unless this_version && other_version

        (this_version <=> other_version) == 1
      end

      private

      sig { params(version_str: String).returns(T.nilable(T::Array[Integer])) }
      def parse_version(version_str)
        parts = version_str.split(".")
        return unless parts.length == 2

        year = Integer(T.must(parts[0]), 10)
        month = Integer(T.must(parts[1]), 10)
        return unless month.between?(1, 12)

        [year, month]
      rescue ArgumentError
        nil
      end
    end
  end
end
