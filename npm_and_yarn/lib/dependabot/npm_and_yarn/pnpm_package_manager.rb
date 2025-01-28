# typed: strong
# frozen_string_literal: true

require "dependabot/npm_and_yarn/package_manager"

module Dependabot
  module NpmAndYarn
    class PNPMPackageManager < Ecosystem::VersionManager
      extend T::Sig
      NAME = "pnpm"
      LOCKFILE_NAME = "pnpm-lock.yaml"
      PNPM_WS_YML_FILENAME = "pnpm-workspace.yaml"

      PNPM_V7 = "7"
      PNPM_V8 = "8"
      PNPM_V9 = "9"

      SUPPORTED_VERSIONS = T.let([
        Version.new(PNPM_V7),
        Version.new(PNPM_V8),
        Version.new(PNPM_V9)
      ].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          detected_version: T.nilable(String),
          raw_version: T.nilable(String),
          requirement: T.nilable(Dependabot::NpmAndYarn::Requirement)
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
