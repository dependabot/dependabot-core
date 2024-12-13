# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/dotnet_sdk/file_fetcher"
require "dependabot/dotnet_sdk/file_parser"
require "dependabot/dotnet_sdk/update_checker"
require "dependabot/dotnet_sdk/file_updater"
require "dependabot/dotnet_sdk/metadata_finder"
require "dependabot/dotnet_sdk/requirement"
require "dependabot/dotnet_sdk/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("dotnet_sdk", name: "dotnet_sdk_package_manager", colour: "512BD4")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check("dotnet_sdk", ->(_) { true })
