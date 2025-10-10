# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/bazel/file_fetcher"
require "dependabot/bazel/file_parser"
require "dependabot/bazel/update_checker"
require "dependabot/bazel/file_updater"
require "dependabot/bazel/metadata_finder"
require "dependabot/bazel/version"
require "dependabot/bazel/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("bazel", name: "bazel", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("bazel", ->(_) { true })
