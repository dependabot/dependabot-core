# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/composer/file_fetcher"
require "dependabot/composer/file_parser"
require "dependabot/composer/update_checker"
require "dependabot/composer/file_updater"
require "dependabot/composer/metadata_finder"
require "dependabot/composer/requirement"
require "dependabot/composer/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("composer", name: "php", colour: "45229e")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "composer",
  ->(groups) { groups.include?("runtime") }
)
