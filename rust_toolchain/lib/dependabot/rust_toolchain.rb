# typed: strong
# frozen_string_literal: true

require "dependabot/rust_toolchain/file_fetcher"
require "dependabot/rust_toolchain/file_parser"
require "dependabot/rust_toolchain/update_checker"
require "dependabot/rust_toolchain/file_updater"
require "dependabot/rust_toolchain/metadata_finder"
require "dependabot/rust_toolchain/requirement"
require "dependabot/rust_toolchain/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("rust_toolchain", name: "rust_toolchain_package_manager", colour: "D34516")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check("rust_toolchain", ->(_) { true })

module Dependabot
  module RustToolchain
    RUST_TOOLCHAIN_TOML_FILENAME = "rust-toolchain.toml"

    RUST_TOOLCHAIN_FILENAME = "rust-toolchain"

    STABLE_CHANNEL = "stable"

    BETA_CHANNEL = "beta"

    NIGHTLY_CHANNEL = "nightly"

    RUST_GITHUB_URL = "https://github.com/rust-lang/rust"

    ECOSYSTEM = "rust"

    PACKAGE_MANAGER = "rustup"

    SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
  end
end
