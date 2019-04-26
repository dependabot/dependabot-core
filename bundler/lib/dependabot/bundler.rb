# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/bundler/file_fetcher"
require "dependabot/bundler/file_parser"
require "dependabot/bundler/update_checker"
require "dependabot/bundler/file_updater"
require "dependabot/bundler/metadata_finder"
require "dependabot/bundler/requirement"
require "dependabot/bundler/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("bundler", name: "ruby", colour: "ce2d2d")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "bundler",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("runtime")
    return true if groups.include?("default")

    groups.any? { |g| g.include?("prod") }
  end
)
