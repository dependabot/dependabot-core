# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/gradle/file_fetcher"
require "dependabot/gradle/file_parser"
require "dependabot/gradle/update_checker"
require "dependabot/gradle/file_updater"
require "dependabot/gradle/metadata_finder"
require "dependabot/gradle/requirement"
require "dependabot/gradle/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("gradle", name: "java", colour: "ffa221")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("gradle", ->(_) { true })
