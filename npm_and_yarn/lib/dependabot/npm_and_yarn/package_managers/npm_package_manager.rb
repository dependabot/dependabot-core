# typed: strict
# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class NpmPackageManager < Ecosystem::VersionManager
      extend T::Sig
      NAME = "npm"
      RC_FILENAME = ".npmrc"
      LOCKFILE_NAME = "package-lock.json"
      SHRINKWRAP_LOCKFILE_NAME = "npm-shrinkwrap.json"

      NPM_V6 = "6"
      NPM_V7 = "7"
      NPM_V8 = "8"
      NPM_V9 = "9"
      NPM_V10 = "10"

      # Keep versions in ascending order
      SUPPORTED_VERSIONS = T.let([
        Version.new(NPM_V7),
        Version.new(NPM_V8),
        Version.new(NPM_V9),
        Version.new(NPM_V10)
      ].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([Version.new(NPM_V6)].freeze, T::Array[Dependabot::Version])

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
        return false unless detected_version

        return false if unsupported?

        return false unless Dependabot::Experiments.enabled?(:npm_v6_deprecation_warning)

        deprecated_versions.include?(detected_version)
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        return false unless detected_version

        return false unless Dependabot::Experiments.enabled?(:npm_v6_unsupported_error)

        supported_versions.all? { |supported| supported > detected_version }
      end
    end
  end
end
