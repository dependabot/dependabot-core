# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/test_overwrite/file_fetcher"
require "dependabot/test_overwrite/file_parser"
require "dependabot/test_overwrite/update_checker"
require "dependabot/test_overwrite/file_updater"
require "dependabot/test_overwrite/metadata_finder"
require "dependabot/test_overwrite/version"
require "dependabot/test_overwrite/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("test_overwrite", name: "test_overwrite", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("test_overwrite", ->(_) { true })
