# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/gradle/version"

module Dependabot
  module Gradle
    ECOSYSTEM = "gradle"
    PACKAGE_MANAGER = "gradle"
    SUPPORTED_GRADLE_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    # When a version is going to be unsupported, it will be added here
    DEPRECATED_GRADLE_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          PACKAGE_MANAGER,
          Version.new(""),
          Version.new(raw_version),
          DEPRECATED_GRADLE_VERSIONS,
          SUPPORTED_GRADLE_VERSIONS
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
