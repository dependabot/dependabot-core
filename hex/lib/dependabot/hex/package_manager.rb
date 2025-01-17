# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/hex/version"

module Dependabot
  module Hex
    ECOSYSTEM = "hex"
    PACKAGE_MANAGER = "hex"
    SUPPORTED_HEX_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    # When a version is going to be unsupported, it will be added here
    DEPRECATED_HEX_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          name: PACKAGE_MANAGER,
          version: Version.new(raw_version),
          deprecated_versions: DEPRECATED_HEX_VERSIONS,
          supported_versions: SUPPORTED_HEX_VERSIONS
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
