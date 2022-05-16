# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/maven/file_fetcher"
require "dependabot/maven/file_parser"
require "dependabot/maven/update_checker"
require "dependabot/maven/file_updater"
require "dependabot/maven/metadata_finder"
require "dependabot/maven/requirement"
require "dependabot/maven/version"
require "dependabot/maven/registry_client"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("maven", name: "java", colour: "ffa221")

require "dependabot/dependency"
Dependabot::Dependency.
  register_production_check("maven", ->(groups) { groups != ["test"] })

Dependabot::Dependency.
  register_display_name_builder(
    "maven",
    lambda { |name|
      _group_id, artifact_id, _classifier = name.split(":")
      %w(bom library).include?(artifact_id) ? name : artifact_id
    }
  )
