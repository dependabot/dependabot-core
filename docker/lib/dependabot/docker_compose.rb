# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.

require "dependabot/docker"

require "dependabot/docker_compose/file_fetcher"
require "dependabot/docker_compose/file_parser"
require "dependabot/docker_compose/file_updater"

Dependabot::Utils.register_version_class("docker_compose", Dependabot::Docker::Version)
Dependabot::UpdateCheckers.register("docker_compose", Dependabot::Docker::UpdateChecker)
Dependabot::Utils.register_requirement_class("docker_compose", Dependabot::Docker::Requirement)
Dependabot::MetadataFinders.register("docker_compose", Dependabot::Docker::MetadataFinder)

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("docker_compose", name: "docker_compose", colour: "E5F2FC")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("docker_compose", ->(_) { true })
