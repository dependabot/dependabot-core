# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/docker/file_fetcher"
require "dependabot/docker/file_parser"
require "dependabot/docker/update_checker"
require "dependabot/docker/file_updater"
require "dependabot/docker/metadata_finder"
require "dependabot/docker/requirement"
require "dependabot/docker/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("docker", name: "docker", colour: "21ceff")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("docker", ->(_) { true })
