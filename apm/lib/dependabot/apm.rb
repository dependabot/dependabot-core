# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/apm/file_fetcher"
require "dependabot/apm/file_parser"
require "dependabot/apm/update_checker"
require "dependabot/apm/file_updater"
require "dependabot/apm/metadata_finder"
require "dependabot/apm/requirement"
require "dependabot/apm/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("apm", name: "apm", colour: "0e8a16")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check(
    "apm",
    # Production when the explicit "dependencies" marker is present (or when a
    # dependency carries no group information at all). Presence-based rather than
    # "not development", so a package merged from both `dependencies.apm` and
    # `devDependencies.apm` -- whose flattened groups include both markers --
    # stays production, while a `devDependencies`-only entry does not.
    ->(groups) { groups.empty? || groups.include?("dependencies") }
  )
