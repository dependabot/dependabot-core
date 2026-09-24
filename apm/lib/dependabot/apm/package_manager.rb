# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/apm/version"

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
          version: Version.new(raw_version),
          deprecated_versions: DEPRECATED_APM_VERSIONS,
          supported_versions: SUPPORTED_APM_VERSIONS
        )
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
