# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/python/file_fetcher"
require "dependabot/python/file_parser"
require "dependabot/python/update_checker"
require "dependabot/python/file_updater"
require "dependabot/python/metadata_finder"
require "dependabot/python/requirement"
require "dependabot/python/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("pip", name: "python", colour: "2b67c6")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "pip",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("default")

    groups.include?("dependencies")
  end
)
