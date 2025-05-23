# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/rust_toolchain/file_fetcher"
# require "dependabot/rust_toolchain/file_parser"
# require "dependabot/rust_toolchain/update_checker"
# require "dependabot/rust_toolchain/file_updater"
# require "dependabot/rust_toolchain/metadata_finder"
# require "dependabot/rust_toolchain/requirement"
# require "dependabot/rust_toolchain/version"

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
  end
end
