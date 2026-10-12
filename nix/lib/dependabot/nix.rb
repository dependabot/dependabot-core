# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/nix/file_fetcher"
require "dependabot/nix/file_parser"
require "dependabot/nix/update_checker"
require "dependabot/nix/file_updater"
require "dependabot/nix/metadata_finder"
require "dependabot/nix/version"
require "dependabot/nix/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("nix", name: "nix", colour: "3E6399")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check("nix", ->(_) { true })
