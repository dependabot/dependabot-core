# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/powershell/file_fetcher"
require "dependabot/powershell/file_parser"
require "dependabot/powershell/update_checker"
require "dependabot/powershell/file_updater"
require "dependabot/powershell/metadata_finder"
require "dependabot/powershell/version"
require "dependabot/powershell/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("powershell", name: "powershell", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("powershell", ->(_) { true })
