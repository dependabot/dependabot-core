# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Nix
    # Parses and compares nixpkgs branch names used in flake inputs.
    #
    # Valid formats:
    #   nixos-YY.MM, nixpkgs-YY.MM, release-YY.MM
    #   nixos-unstable, nixpkgs-unstable
    #   With optional suffix: -small, -aarch64, -darwin
    #
    # Ordering: unstable > any numbered release; numbered releases compare [YY, MM].
    # Compatibility: two versions are compatible only when prefix and suffix match.
    class NixpkgsVersion
      extend T::Sig
      include Comparable

      BRANCH_PATTERN = T.let(
        /\A(?<prefix>nixos|nixpkgs|release)-(?:(?<major>\d{2})\.(?<minor>\d{2})|(?<unstable>unstable))(?:-(?<suffix>small|aarch64|darwin))?\z/,
        Regexp
      )

      sig { returns(String) }
      attr_reader :branch

      sig { returns(String) }
      attr_reader :prefix

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :release

      sig { returns(T.nilable(String)) }
      attr_reader :suffix

      sig { params(branch: String).void }
      def initialize(branch)
        match = BRANCH_PATTERN.match(branch)
        raise ArgumentError, "Invalid nixpkgs branch: #{branch.inspect}" unless match

        @branch = T.let(branch, String)
        @prefix = T.let(T.must(match[:prefix]), String)
        @suffix = T.let(match[:suffix], T.nilable(String))

        @release = T.let(
          if match[:unstable]
            nil
          else
            [T.must(match[:major]).to_i, T.must(match[:minor]).to_i]
          end,
          T.nilable(T::Array[Integer])
        )
      end

      sig { params(branch: String).returns(T::Boolean) }
      def self.valid?(branch)
        BRANCH_PATTERN.match?(branch)
      end

      sig { returns(T::Boolean) }
      def unstable?
        release.nil?
      end

      sig { returns(T::Boolean) }
      def stable?
        !unstable?
      end

      sig { returns(String) }
      def compatibility
        suffix ? "#{prefix}-#{suffix}" : prefix
      end

      sig { params(other: NixpkgsVersion).returns(T::Boolean) }
      def compatible_with?(other)
        compatibility == other.compatibility
      end

      sig { override.params(other: BasicObject).returns(T.nilable(Integer)) }
      def <=>(other)
        return nil unless T.unsafe(other).is_a?(NixpkgsVersion)

        other_version = T.cast(other, NixpkgsVersion)

        # Both unstable → equal
        return 0 if unstable? && other_version.unstable?

        # Unstable > any numbered release
        return 1 if unstable?
        return -1 if other_version.unstable?

        # Compare [major, minor] arrays
        T.must(release) <=> T.must(other_version.release)
      end

      sig { returns(String) }
      def to_s
        branch
      end

      sig { override.params(other: BasicObject).returns(T::Boolean) }
      def ==(other)
        case other
        when NixpkgsVersion
          branch == other.branch
        else
          false
        end
      end

      sig { override.returns(Integer) }
      def hash
        branch.hash
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def eql?(other)
        self == other
      end
    end
  end
end
