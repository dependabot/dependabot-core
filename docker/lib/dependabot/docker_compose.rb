# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/docker_compose/file_fetcher"
require "dependabot/docker_compose/file_parser"
require "dependabot/docker_compose/update_checker"
require "dependabot/docker_compose/file_updater"
require "dependabot/docker_compose/metadata_finder"
require "dependabot/docker_compose/requirement"
require "dependabot/docker_compose/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("docker_compose", name: "docker", colour: "21ceff")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "docker_compose",
  ->(_) { true }
)
