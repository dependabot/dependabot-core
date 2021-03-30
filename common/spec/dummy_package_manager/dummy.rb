# frozen_string_literal: true

require_relative "metadata_finder"
require_relative "requirement"
require_relative "version"

require "dependabot/pull_request_creator/labelers/package_manager_labels"
Dependabot::PullRequestCreator::Labelers::PackageManagerLabels.
  register_label("dummy", name: "ruby", colour: "ce2d2d")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "dummy",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("runtime")
    return true if groups.include?("default")

    groups.any? { |g| g.include?("prod") }
  end
)
