# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/version"
require "dependabot/kotlin_toolchain/requirement"
require "dependabot/kotlin_toolchain/package_manager"
require "dependabot/kotlin_toolchain/yaml_parser"
require "dependabot/kotlin_toolchain/file_fetcher"
require "dependabot/kotlin_toolchain/file_parser"
require "dependabot/kotlin_toolchain/update_checker"
require "dependabot/kotlin_toolchain/file_updater"
require "dependabot/kotlin_toolchain/metadata_finder"

require "dependabot/dependency"
require "dependabot/pull_request_creator/labeler"

Dependabot::PullRequestCreator::Labeler
  .register_label_details("kotlin_toolchain", name: "kotlin_toolchain_package_manager", colour: "7F52FF")

Dependabot::Dependency.register_production_check(
  "kotlin_toolchain",
  ->(groups) { groups.include?("dependencies") || !groups.include?("test") }
)
Dependabot::Dependency.register_display_name_builder(
  "kotlin_toolchain",
  ->(name) { name == "org.jetbrains.kotlin:kotlin-cli" ? "kotlin-toolchain" : name }
)
