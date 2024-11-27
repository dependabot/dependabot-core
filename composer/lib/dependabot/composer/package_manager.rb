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
      PLUGIN_API_KEY = "composer-plugin-api"

      # Keep versions in ascending order
      SUPPORTED_COMPOSER_VERSIONS = T.let([Version.new("2")].freeze, T::Array[Dependabot::Version])

      DEPRECATED_COMPOSER_VERSIONS = T.let([
        Version.new("1")
      ].freeze, T::Array[Dependabot::Version])

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          NAME,
          Version.new(raw_version),
          DEPRECATED_COMPOSER_VERSIONS,
          SUPPORTED_COMPOSER_VERSIONS,
       )
      end
    end
  end
end
