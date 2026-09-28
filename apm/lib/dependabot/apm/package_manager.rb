# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/version"

module Dependabot
  module Apm
    ECOSYSTEM = "apm"
    PACKAGE_MANAGER = "apm"

    # The default version reported when the resolved apm CLI version cannot be
    # determined from the lockfile (`apm_version`).
    DEFAULT_PACKAGE_MANAGER_VERSION = "0.0.0"

    SUPPORTED_APM_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
    DEPRECATED_APM_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          name: PACKAGE_MANAGER,
          version: PackageManager.parse_version(raw_version),
          deprecated_versions: DEPRECATED_APM_VERSIONS,
          supported_versions: SUPPORTED_APM_VERSIONS
        )
      end

      # The apm CLI version recorded in the lockfile (`apm_version`) is written
      # by apm from its Python (PEP 440) distribution metadata, and the lockfile
      # schema permits an arbitrary string, so it is not necessarily strict
      # SemVer (e.g. `0.32.0rc1`, `0.32.0.dev3`). Parse it with the permissive
      # base version rather than the strict Apm::Version — which is meant for
      # dependency git refs and would raise ArgumentError here — falling back to
      # the default when the string cannot be represented at all, so an unusual
      # CLI version never prevents parsing the project.
      sig { params(raw_version: String).returns(Dependabot::Version) }
      def self.parse_version(raw_version)
        return Dependabot::Version.new(raw_version) if Dependabot::Version.correct?(raw_version)

        Dependabot::Version.new(DEFAULT_PACKAGE_MANAGER_VERSION)
      end

      sig { returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
