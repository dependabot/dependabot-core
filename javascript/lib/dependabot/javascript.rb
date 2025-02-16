# typed: strong
# frozen_string_literal: true

require "dependabot/bun"

module Dependabot
  module Javascript
    DEFAULT_PACKAGE_MANAGER = "npm"
    ERROR_MALFORMED_VERSION_NUMBER = "Malformed version number"
    MANIFEST_ENGINES_KEY = "engines"
    MANIFEST_FILENAME = "package.json"
    MANIFEST_PACKAGE_MANAGER_KEY = "packageManager"

    # Define a type alias for the expected class interface
    JavascriptPackageManagerClassType = T.type_alias do
      T.class_of(Bun::PackageManager)
    end

    PACKAGE_MANAGER_CLASSES = T.let({
      Bun::PackageManager::NAME => Bun::PackageManager
    }.freeze, T::Hash[String, JavascriptPackageManagerClassType])

    PACKAGE_MANAGER_VERSION_REGEX = /
      ^                        # Start of string
      (?<major>\d+)            # Major version (required, numeric)
      \.                       # Separator between major and minor versions
      (?<minor>\d+)            # Minor version (required, numeric)
      \.                       # Separator between minor and patch versions
      (?<patch>\d+)            # Patch version (required, numeric)
      (                        # Start pre-release section
        -(?<pre_release>[a-zA-Z0-9.]+) # Pre-release label (optional, alphanumeric or dot-separated)
      )?
      (                        # Start build metadata section
        \+(?<build>[a-zA-Z0-9.]+) # Build metadata (optional, alphanumeric or dot-separated)
      )?
      $                        # End of string
    /x # Extended mode for readability
  end
end
