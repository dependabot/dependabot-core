# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/cake/file_fetcher"
require "dependabot/cake/file_parser"
require "dependabot/cake/update_checker"
require "dependabot/cake/file_updater"
require "dependabot/cake/metadata_finder"
require "dependabot/cake/version"
require "dependabot/cake/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("cake", name: "cake", colour: "7121c6")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("cake", ->(_) { true })
