# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/silent/file_fetcher"
require "dependabot/silent/file_parser"
require "dependabot/silent/update_checker"
require "dependabot/silent/file_updater"
# require "dependabot/silent/metadata_finder" TODO
require "dependabot/silent/requirement"
require "dependabot/silent/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("silent", name: "silent_package_manager", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check("silent", ->(groups) { groups.empty? || groups.include?("prod") })
