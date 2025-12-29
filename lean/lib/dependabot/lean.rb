# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# Dependabot
require "dependabot/dependency"
require "dependabot/pull_request_creator/labeler"

# Lean ecosystem components
require "dependabot/lean/version"
require "dependabot/lean/requirement"
require "dependabot/lean/file_fetcher"
require "dependabot/lean/file_parser"
require "dependabot/lean/update_checker"
require "dependabot/lean/file_updater"
require "dependabot/lean/metadata_finder"
require "dependabot/lean/package_manager"

module Dependabot
  module Lean
    extend T::Sig

    ECOSYSTEM = "lean"
    PACKAGE_MANAGER = "lean"
    LANGUAGE = "lean"

    LEAN_TOOLCHAIN_FILENAME = "lean-toolchain"
    LEAN_GITHUB_REPO = "leanprover/lean4"
    LEAN_GITHUB_URL = "https://github.com/leanprover/lean4"

    # Toolchain file format: leanprover/lean4:v{version}
    TOOLCHAIN_PREFIX = "leanprover/lean4:v"

    # Lake package manager files
    LAKE_MANIFEST_FILENAME = "lake-manifest.json"
    LAKEFILE_TOML_FILENAME = "lakefile.toml"
    LAKEFILE_LEAN_FILENAME = "lakefile.lean"

    SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
    DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
  end
end

Dependabot::PullRequestCreator::Labeler.register_label_details(
  "lean",
  name: "lean",
  colour: "2c2c32"
)

Dependabot::Dependency.register_production_check("lean", ->(_) { true })
