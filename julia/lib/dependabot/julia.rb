# typed: strict
# frozen_string_literal: true

require "dependabot/julia/file_fetcher"
require "dependabot/julia/toml_parser"
require "dependabot/julia/update_checker"
require "dependabot/julia/file_updater"
require "dependabot/julia/version"
require "dependabot/julia/requirement"
require "dependabot/julia/helpers"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("julia", name: "julia", colour: "a270ba")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("julia", ->(_) { true })
