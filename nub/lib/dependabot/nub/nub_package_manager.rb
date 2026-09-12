# typed: strong
# frozen_string_literal: true

module Dependabot
  module Nub
    class NubPackageManager < Ecosystem::VersionManager
      extend T::Sig

      NAME = "nub"
      LOCKFILE_NAME = "nub.lock"
      RC_FILENAME = ".npmrc"

      # nub writes `nub.lock`, which is byte-compatible with the pnpm lockfile v9 format
      # (a rename-only transform of pnpm-lock.yaml). It is parsed via the shared pnpm parser.
      # See https://github.com/nubjs/nub
      # TODO: track nub's first release that stabilises `nub.lock`; 0.0.1 is a conservative floor.
      MIN_SUPPORTED_VERSION = Version.new("0.0.1")
      SUPPORTED_VERSIONS = T.let([MIN_SUPPORTED_VERSION].freeze, T::Array[Dependabot::Version])
      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          detected_version: T.nilable(String),
          raw_version: T.nilable(String),
          requirement: T.nilable(Dependabot::Nub::Requirement)
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
