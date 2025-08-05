# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/conda/file_fetcher"
require "dependabot/conda/file_parser"
require "dependabot/conda/update_checker"
require "dependabot/conda/file_updater"
require "dependabot/conda/metadata_finder"
require "dependabot/conda/requirement"
require "dependabot/conda/version"
require "dependabot/conda/name_normaliser"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("conda", name: "conda", colour: "44a047")

require "dependabot/dependency"
# Conda manages Python packages, so use the same production check as Python
Dependabot::Dependency.register_production_check(
  "conda",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("default")
    return true if groups.include?("dependencies")

    groups.include?("pip")
  end
)

Dependabot::Dependency.register_name_normaliser(
  "conda",
  ->(name) { Dependabot::Conda::NameNormaliser.normalise(name) }
)
