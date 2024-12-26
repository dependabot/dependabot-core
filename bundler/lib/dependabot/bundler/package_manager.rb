# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bundler/version"
require "dependabot/ecosystem"
require "dependabot/bundler/requirement"

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

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig do
        params(
          detected_version: T.nilable(String),
          raw_version: T.nilable(String),
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version, raw_version, requirement = nil)
        super(
          PACKAGE_MANAGER,
          detected_version ? Version.new(detected_version) : nil,
          raw_version ? Version.new(raw_version) : nil,
          DEPRECATED_BUNDLER_VERSIONS,
          SUPPORTED_BUNDLER_VERSIONS,
          requirement,
       )
      end
    end
  end
end
