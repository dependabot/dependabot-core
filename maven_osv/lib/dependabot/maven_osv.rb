# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/maven_osv/file_fetcher"
require "dependabot/maven_osv/file_parser"
require "dependabot/maven_osv/update_checker"
require "dependabot/maven_osv/file_updater"
require "dependabot/maven_osv/metadata_finder"
require "dependabot/maven_osv/requirement"
require "dependabot/maven_osv/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("maven_osv", name: "java", colour: "ffa221")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check("maven_osv", ->(groups) { groups != ["test"] })

Dependabot::Dependency
  .register_display_name_builder(
    "maven_osv",
    lambda { |name|
      _group_id, artifact_id = name.split(":")
      name.length <= 100 ? name : artifact_id
    }
  )
