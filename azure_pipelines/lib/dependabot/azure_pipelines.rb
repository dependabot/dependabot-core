# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/azure_pipelines/file_fetcher"
require "dependabot/azure_pipelines/file_parser"
require "dependabot/azure_pipelines/update_checker"
require "dependabot/azure_pipelines/file_updater"
# require "dependabot/azure_pipelines/metadata_finder"
require "dependabot/azure_pipelines/requirement"
require "dependabot/azure_pipelines/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("azure_pipelines", name: "azure_pipelines_package_manager", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check("azure_pipelines", ->(_) { true })
