# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/haskell/file_fetcher"
require "dependabot/haskell/file_parser"
require "dependabot/haskell/update_checker"
require "dependabot/haskell/file_updater"
require "dependabot/haskell/metadata_finder"
require "dependabot/haskell/requirement"
require "dependabot/haskell/version"
require "dependabot/haskell/pull_request_creator/labeler"
require "dependabot/haskell/metadata_finders/base/changelog_finder"

Dependabot::Haskell:PullRequestCreator::Labeler.
  register_label_details(
    "haskell",
    name: "haskell",
    colour: "5e5086"
  )

require "dependabot/dependency"
Dependabot::Dependency.
  register_production_check("haskell", ->(_) { true })
