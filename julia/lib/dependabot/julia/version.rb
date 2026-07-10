# typed: strong
# frozen_string_literal: true

require "dependabot/version"

module Dependabot
  module Julia
    class Version < Dependabot::Version
      # Julia follows semantic versioning, including prerelease tags and build
      # metadata. Build metadata is significant in Julia: JLL packages register
      # versions like "1.6.10+0", "1.6.10+1" where the build number orders new
      # builds of the same upstream version.
      # See: https://docs.julialang.org/en/v1/stdlib/Pkg/#Version-specifier-format
      VERSION_PATTERN = T.let(
        /^v?\d+(?:\.\d+)*(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/,
        Regexp
      )

      sig { override.params(version: T.nilable(T.any(String, Integer, Gem::Version))).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        VERSION_PATTERN.match?(version.to_s.strip)
      end

      sig { override.params(version: T.nilable(T.any(String, Integer, Gem::Version))).void }
      def initialize(version)
        version_string = version.to_s.strip

        # Remove 'v' prefix if present (common in Julia)
        version_string = version_string.sub(/^v/, "") if version_string.match?(/^v\d/)

        @version_string = T.let(version_string, String)
        super(self.class.gem_compatible_version_string(version_string))
      end

      sig do
        override
          .params(version: T.nilable(T.any(String, Integer, Gem::Version)))
          .returns(Dependabot::Julia::Version)
      end
      def self.new(version)
        T.cast(super, Dependabot::Julia::Version)
      end

      # Gem::Version rejects "+" so build metadata has to be folded away before
      # calling super. A numeric build becomes an extra segment, which preserves
      # Julia's ordering between builds ("1.6.10+1" > "1.6.10+0") and against
      # neighbouring versions ("1.6.10+1" < "1.6.11"). Non-numeric builds are
      # dropped for comparison purposes.
      sig { params(version_string: String).returns(String) }
      def self.gem_compatible_version_string(version_string)
        base, build = version_string.split("+", 2)
        return version_string unless build

        build.match?(/\A\d+\z/) ? "#{base}.#{build}" : T.must(base)
      end

      sig { returns(String) }
      def to_s
        @version_string
      end

      sig { override.returns(String) }
      def to_semver
        @version_string
      end
    end
  end
end

Dependabot::Utils.register_version_class("julia", Dependabot::Julia::Version)
