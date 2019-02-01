# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/cargo/file_fetcher"
require "dependabot/cargo/file_parser"
require "dependabot/cargo/update_checker"
require "dependabot/cargo/file_updater"
require "dependabot/cargo/metadata_finder"
require "dependabot/cargo/requirement"
require "dependabot/cargo/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("cargo", name: "rust", colour: "000000")
