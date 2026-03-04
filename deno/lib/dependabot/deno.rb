# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/deno/file_fetcher"
require "dependabot/deno/file_parser"
require "dependabot/deno/update_checker"
require "dependabot/deno/file_updater"
require "dependabot/deno/metadata_finder"
require "dependabot/deno/version"
require "dependabot/deno/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("deno", name: "deno", colour: "70ffaf")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("deno", ->(_) { true })
