# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/nuget/file_fetcher"
require "dependabot/nuget/file_parser"
require "dependabot/nuget/update_checker"
require "dependabot/nuget/file_updater"
require "dependabot/nuget/metadata_finder"
require "dependabot/nuget/requirement"
require "dependabot/nuget/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("nuget", name: ".NET", colour: "7121c6")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "nuget",
  lambda do |groups|
    return true if groups.empty?

    groups.include?("dependencies")
  end
)
