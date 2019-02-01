# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/hex/file_fetcher"
require "dependabot/hex/file_parser"
require "dependabot/hex/update_checker"
require "dependabot/hex/file_updater"
require "dependabot/hex/metadata_finder"
require "dependabot/hex/requirement"
require "dependabot/hex/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("hex", name: "elixir", colour: "9380dd")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "hex",
  lambda do |groups|
    return true if groups.empty?

    groups.any? { |g| g.include?("prod") }
  end
)
