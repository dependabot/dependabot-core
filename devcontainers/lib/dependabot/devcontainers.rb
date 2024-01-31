# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/devcontainers/file_fetcher"
require "dependabot/devcontainers/file_parser"
require "dependabot/devcontainers/update_checker"
require "dependabot/devcontainers/file_updater"
require "dependabot/devcontainers/metadata_finder"
require "dependabot/devcontainers/requirement"
require "dependabot/devcontainers/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("devcontainers", name: "devcontainers_package_manager", colour: "2753E3")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check("devcontainers", ->(_) { true })
