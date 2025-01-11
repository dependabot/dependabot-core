# typed: strict
# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class YarnPackageManager < Ecosystem::VersionManager
      extend T::Sig
      NAME = "yarn"
      RC_FILENAME = ".yarnrc"
      RC_YML_FILENAME = ".yarnrc.yml"
      LOCKFILE_NAME = "yarn.lock"

      YARN_V1 = "1"
      YARN_V2 = "2"
      YARN_V3 = "3"

      SUPPORTED_VERSIONS = T.let([
        Version.new(YARN_V1),
        Version.new(YARN_V2),
        Version.new(YARN_V3)
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
