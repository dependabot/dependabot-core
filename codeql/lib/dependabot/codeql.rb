# typed: strict
# frozen_string_literal: true

require "dependabot/codeql/file_fetcher"
require "dependabot/codeql/file_parser"
require "dependabot/codeql/update_checker"
require "dependabot/codeql/file_updater"
require "dependabot/codeql/metadata_finder"
require "dependabot/codeql/package_manager"
require "dependabot/codeql/requirement"
require "dependabot/codeql/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("codeql", name: "codeql", colour: "3D67FF")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("codeql", ->(_groups) { true })
