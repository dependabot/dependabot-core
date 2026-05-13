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

    # Keep versions in ascending order.
    # Note: Bundler 3 was intentionally skipped upstream — Bundler jumped from
    # 2.7 directly to 4.0 to align its major version with RubyGems, so there
    # is no Bundler 3.x release to support.
    SUPPORTED_BUNDLER_VERSIONS = T.let(
      [Version.new("2"), Version.new("4")].freeze,
      T::Array[Dependabot::Version]
    )

    # Currently, we don't support any deprecated versions of Bundler
    # When a version is going to be unsupported, it will be added here for a while to give users time to upgrade
    # Example for deprecation:
    # DEPRECATED_BUNDLER_VERSIONS = T.let([Version.new("1")].freeze, T::Array[Dependabot::Version])
    DEPRECATED_BUNDLER_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig do
        params(
          detected_version: String,
          raw_version: T.nilable(String),
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version:, raw_version: nil, requirement: nil)
        super(
          name: PACKAGE_MANAGER,
          detected_version: Version.new(detected_version),
          version: raw_version ? Version.new(raw_version) : nil,
          deprecated_versions: DEPRECATED_BUNDLER_VERSIONS,
          supported_versions: SUPPORTED_BUNDLER_VERSIONS,
          requirement: requirement,
       )
      end
    end
  end
end
