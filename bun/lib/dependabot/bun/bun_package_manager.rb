# typed: strong
# frozen_string_literal: true

module Dependabot
  module Bun
    class BunPackageManager < Ecosystem::VersionManager
      extend T::Sig

      NAME = "bun"
      LOCKFILE_NAME = "bun.lock"
      RC_FILENAME = ".npmrc"

      # In Bun 1.1.39, the lockfile format was changed from a binary bun.lockb to a text-based bun.lock.
      # https://bun.sh/blog/bun-lock-text-lockfile
      MIN_SUPPORTED_VERSION = Version.new("1.1.39")

      # The highest bun.lock `lockfileVersion` the bun binary bundled in `bun/Dockerfile` can parse.
      # Bun 1.4 raised the default to 2 (https://github.com/oven-sh/bun/pull/31539), which the bundled
      # bun rejects at parse time. Bump this in lockstep with `ARG BUN_VERSION` in `bun/Dockerfile`.
      MAX_SUPPORTED_LOCKFILE_VERSION = 1
      SUPPORTED_VERSIONS = T.let([MIN_SUPPORTED_VERSION].freeze, T::Array[Dependabot::Version])
      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          detected_version: T.nilable(String),
          raw_version: T.nilable(String),
          requirement: T.nilable(Dependabot::Bun::Requirement)
        ).void
      end
      def initialize(detected_version: nil, raw_version: nil, requirement: nil)
        super(
          name: NAME,
          detected_version: detected_version ? Version.new(detected_version) : nil,
          version: raw_version ? Version.new(raw_version) : nil,
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS,
          requirement: requirement
        )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
