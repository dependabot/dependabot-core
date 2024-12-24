# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/swift/version"

module Dependabot
  module Swift
    ECOSYSTEM = "swift"
    PACKAGE_MANAGER = "swift"
    SUPPORTED_SWIFT_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    # When a version is going to be unsupported, it will be added here
    DEPRECATED_SWIFT_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          PACKAGE_MANAGER,
          Version.new(""),
          Version.new(raw_version),
          DEPRECATED_SWIFT_VERSIONS,
          SUPPORTED_SWIFT_VERSIONS
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
