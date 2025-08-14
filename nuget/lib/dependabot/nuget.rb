# typed: strict
# frozen_string_literal: true

# These files are part of the Dependabot Core library, which provides
# functionality for managing dependencies across various ecosystems.
# This file specifically handles the NuGet package management system.
require "dependabot/nuget/requirement"
require "dependabot/nuget/version"


require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("nuget", name: ".NET", colour: "7121c6")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "nuget",
  lambda do |groups|
    return true if groups.empty?

    groups.include?("dependencies")
  end
)
