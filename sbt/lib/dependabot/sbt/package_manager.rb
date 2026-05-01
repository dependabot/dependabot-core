# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/sbt/version"

module Dependabot
  module Sbt
    ECOSYSTEM = "sbt"
    PACKAGE_MANAGER = "sbt"
    SUPPORTED_SBT_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
    DEPRECATED_SBT_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          name: PACKAGE_MANAGER,
          version: Version.new(raw_version),
          deprecated_versions: DEPRECATED_SBT_VERSIONS,
          supported_versions: SUPPORTED_SBT_VERSIONS
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
