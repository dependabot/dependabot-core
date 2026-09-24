# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/apm/file_fetcher"
require "dependabot/apm/file_parser"
require "dependabot/apm/update_checker"
require "dependabot/apm/file_updater"
require "dependabot/apm/metadata_finder"
require "dependabot/apm/requirement"
require "dependabot/apm/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("apm", name: "apm", colour: "0e8a16")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check(
    "apm",
    ->(groups) { !groups.include?("development") }
  )
