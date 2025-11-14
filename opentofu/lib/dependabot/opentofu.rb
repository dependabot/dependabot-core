# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/opentofu/file_fetcher"
require "dependabot/opentofu/file_parser"
require "dependabot/opentofu/update_checker"
require "dependabot/opentofu/file_updater"
require "dependabot/opentofu/metadata_finder"
require "dependabot/opentofu/requirement"
require "dependabot/opentofu/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("opentofu", name: "opentofu", colour: "F9DB4E")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check("opentofu", ->(_) { true })

Dependabot::Dependency
  .register_display_name_builder(
    "opentofu",
    lambda { |name|
      # Only modify the name if it a git source dependency
      return name unless name.include? "::"

      name.split("::").first + "::" + name.split("::")[2].split("/").last.split("(").first
    }
  )
