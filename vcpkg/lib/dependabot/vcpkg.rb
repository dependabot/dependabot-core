# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/vcpkg/language"
require "dependabot/vcpkg/package_manager"
require "dependabot/vcpkg/file_fetcher"
require "dependabot/vcpkg/file_parser"
require "dependabot/vcpkg/update_checker"
require "dependabot/vcpkg/file_updater"
require "dependabot/vcpkg/metadata_finder"
require "dependabot/vcpkg/requirement"
require "dependabot/vcpkg/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("vcpkg", name: "vcpkg_package_manager", colour: "FBCA04")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("vcpkg", ->(_) { true })

module Dependabot
  module Vcpkg
    extend T::Sig

    ECOSYSTEM = "vcpkg"

    PACKAGE_MANAGER = "vcpkg"

    LANGUAGE = "cpp"

    # See: https://learn.microsoft.com/vcpkg/reference/vcpkg-json
    VCPKG_JSON_FILENAME = "vcpkg.json"

    # See: https://learn.microsoft.com/vcpkg/reference/vcpkg-configuration-json
    VCPKG_CONFIGURATION_JSON_FILENAME = "vcpkg-configuration.json"

    VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME = "github.com/microsoft/vcpkg"

    VCPKG_DEFAULT_BASELINE_URL = "https://github.com/microsoft/vcpkg.git"

    # Repository URL without the `.git` suffix, for generated `default-registry` blocks.
    VCPKG_DEFAULT_REGISTRY_REPOSITORY = "https://github.com/microsoft/vcpkg"

    VCPKG_DEFAULT_BASELINE_DEFAULT_BRANCH = "master"

    VCPKG_SUPPORTED_REGISTRY_TYPES = %w(git builtin).freeze

    # Manifest keys. See https://learn.microsoft.com/vcpkg/reference/vcpkg-json
    VCPKG_BUILTIN_BASELINE_KEY = "builtin-baseline"

    VCPKG_DEPENDENCIES_KEY = "dependencies"

    VCPKG_OVERRIDES_KEY = "overrides"

    VCPKG_VERSION_CONSTRAINT_KEY = "version>="

    # The vcpkg checkout the updater image ships, holding the ports tree and versions database.
    VCPKG_DEFAULT_REPOSITORY_PATH = "/opt/vcpkg"

    # See https://learn.microsoft.com/vcpkg/users/versioning#version-schemes
    VCPKG_VERSION_SCHEME_KEYS = %w(version version-semver version-date version-string).freeze

    VCPKG_BASELINE_DATABASE_PATH = "versions/baseline.json"

    VCPKG_VERSIONS_DIRECTORY = "versions"

    # vcpkg publishes releases as date tags such as `2025.06.13`.
    VCPKG_RELEASE_TAG_PATTERN = /\Av?\d{4}\.\d{2}\.\d{2}\z/

    sig { returns(String) }
    def self.repository_path
      ENV.fetch("VCPKG_ROOT", VCPKG_DEFAULT_REPOSITORY_PATH)
    end
  end
end
