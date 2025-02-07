# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/composer/version"

module Dependabot
  module Composer
    ECOSYSTEM = "composer"

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "composer"
      MANIFEST_FILENAME = "composer.json"
      LOCKFILE_FILENAME = "composer.lock"
      AUTH_FILENAME = "auth.json"
      DEPENDENCY_NAME = "composer/composer"

      REQUIRE_KEY = "require"
      CONFIG_KEY = "config"
      PLATFORM_KEY = "platform"
      PLUGIN_API_VERSION_KEY = "plugin-api-version"
      REPOSITORY_KEY = "composer_repository"

      # Keep versions in ascending order
      SUPPORTED_COMPOSER_VERSIONS = T.let([Version.new("2")].freeze, T::Array[Dependabot::Version])

      # Currently, we don't support any deprecated versions of Composer
      # When a version is going to be unsupported, it will be added here for a while to give users time to upgrade
      # Example for deprecation:
      # DEPRECATED_COMPOSER_VERSIONS = T.let([Version.new("1")].freeze, T::Array[Dependabot::Version])
      DEPRECATED_COMPOSER_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          detected_version: String,
          raw_version: T.nilable(String)
        ).void
      end
      def initialize(detected_version:, raw_version: nil)
        super(
          name: NAME,
          detected_version: Version.new(detected_version),
          version: raw_version ? Version.new(raw_version) : nil,
          deprecated_versions: DEPRECATED_COMPOSER_VERSIONS,
          supported_versions: SUPPORTED_COMPOSER_VERSIONS
       )
      end
    end
  end
end
