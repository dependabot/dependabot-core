# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/nimble/file_fetcher"
require "dependabot/nimble/file_parser"
require "dependabot/nimble/update_checker"
require "dependabot/nimble/file_updater"
require "dependabot/nimble/metadata_finder"
require "dependabot/nimble/version"
require "dependabot/nimble/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("nimble", name: "nimble", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("nimble", ->(_) { true })
