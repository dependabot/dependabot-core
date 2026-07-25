# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/azure_pipelines/file_fetcher"
require "dependabot/azure_pipelines/file_parser"
require "dependabot/azure_pipelines/update_checker"
require "dependabot/azure_pipelines/file_updater"
require "dependabot/azure_pipelines/metadata_finder"
require "dependabot/azure_pipelines/version"
require "dependabot/azure_pipelines/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("azure_pipelines", name: "azure-pipelines", colour: "0078d4")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("azure_pipelines", ->(_) { true })
