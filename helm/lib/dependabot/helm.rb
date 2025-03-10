# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.

require "dependabot/docker"

require "dependabot/helm/file_fetcher"
require "dependabot/helm/file_parser"
require "dependabot/helm/file_updater"
require "dependabot/helm/update_checker"

Dependabot::Utils.register_version_class("helm", Dependabot::Docker::Version)
Dependabot::Utils.register_requirement_class("helm", Dependabot::Docker::Requirement)
Dependabot::MetadataFinders.register("helm", Dependabot::Docker::MetadataFinder)

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("helm", name: "helm", colour: "E5F2FC")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("helm", ->(_) { true })
