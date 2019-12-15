# frozen_string_literal: true

require "dependabot/sbt/file_fetcher"
require "dependabot/sbt/file_updater"
require "dependabot/sbt/file_parser"
require "dependabot/sbt/update_checker"
require "dependabot/sbt/metadata_finder"
require "dependabot/sbt/version"
require "dependabot/sbt/requirement"

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("sbt", name: "scala", colour: "ffa221")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("sbt", ->(_) { true })

Dependabot::Dependency.
  register_display_name_builder(
    "sbt",
    lambda { |name|
      artifact_id = name.split(":").last
      %w(bom library).include?(artifact_id) ? name : artifact_id
    }
  )
