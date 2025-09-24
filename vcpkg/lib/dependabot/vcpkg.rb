# typed: strong
# frozen_string_literal: true

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
    ECOSYSTEM = "vcpkg"

    PACKAGE_MANAGER = "vcpkg"

    LANGUAGE = "cpp"

    # See: https://learn.microsoft.com/vcpkg/reference/vcpkg-json
    VCPKG_JSON_FILENAME = "vcpkg.json"

    # See: https://learn.microsoft.com/vcpkg/reference/vcpkg-configuration-json
    VCPKG_CONFIGURATION_JSON_FILENAME = "vcpkg-configuration.json"

    VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME = "github.com/microsoft/vcpkg"

    VCPKG_DEFAULT_BASELINE_URL = "https://github.com/microsoft/vcpkg.git"

    VCPKG_DEFAULT_BASELINE_DEFAULT_BRANCH = "master"
  end
end
