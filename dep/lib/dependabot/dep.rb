# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/dep/file_fetcher"
require "dependabot/dep/file_parser"
require "dependabot/dep/update_checker"
require "dependabot/dep/file_updater"
require "dependabot/dep/metadata_finder"
require "dependabot/dep/requirement"
require "dependabot/dep/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("dep", name: "go", colour: "16e2e2")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("dep", ->(groups) { true })
