# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/github_actions/file_fetcher"
require "dependabot/github_actions/file_parser"
require "dependabot/github_actions/update_checker"
require "dependabot/github_actions/file_updater"
require "dependabot/github_actions/metadata_finder"
require "dependabot/github_actions/requirement"
require "dependabot/github_actions/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details(
    "github_actions",
    name: "github_actions",
    description: "Pull requests that update GitHub Actions code",
    colour: "000000"
  )

require "dependabot/dependency"
Dependabot::Dependency.
  register_production_check("github_actions", ->(_) { true })
