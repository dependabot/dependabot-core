# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/git_submodules/file_fetcher"
require "dependabot/git_submodules/file_parser"
require "dependabot/git_submodules/update_checker"
require "dependabot/git_submodules/file_updater"
require "dependabot/git_submodules/metadata_finder"
require "dependabot/git_submodules/requirement"
require "dependabot/git_submodules/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("submodules", name: "submodules", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.
  register_production_check("submodules", ->(_) { true })
