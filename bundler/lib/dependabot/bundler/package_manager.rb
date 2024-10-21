# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bundler/version"
require "dependabot/package_manager"

module Dependabot
  module Bundler
    ECOSYSTEM = "bundler"
    PACKAGE_MANAGER = "bundler"

    # Keep versions in ascending order
    SUPPORTED_BUNDLER_VERSIONS = T.let([Version.new("2")].freeze, T::Array[Dependabot::Version])

    # Currently, we don't support any deprecated versions of Bundler
    # When a version is going to be unsupported, it will be added here for a while to give users time to upgrade
    # Example for deprecation:
    # DEPRECATED_BUNDLER_VERSIONS = T.let([Version.new("1")].freeze, T::Array[Dependabot::Version])
    DEPRECATED_BUNDLER_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < PackageManagerBase
      extend T::Sig

      sig { params(version: T.any(String, Dependabot::Version)).void }
      def initialize(version)
        super(
          ECOSYSTEM,
          PACKAGE_MANAGER,
          Version.new(version),
          DEPRECATED_BUNDLER_VERSIONS,
          SUPPORTED_BUNDLER_VERSIONS
        )
      end
    end
  end
end
