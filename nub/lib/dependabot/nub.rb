# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/nub/file_fetcher"
require "dependabot/nub/file_parser"
require "dependabot/nub/update_checker"
require "dependabot/nub/file_updater"
require "dependabot/nub/metadata_finder"
require "dependabot/nub/requirement"
require "dependabot/nub/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("nub", name: "javascript", colour: "168700")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "nub",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("optionalDependencies")

    groups.include?("dependencies")
  end
)
