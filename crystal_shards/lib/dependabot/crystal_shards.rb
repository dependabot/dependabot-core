# typed: strict
# frozen_string_literal: true

require "dependabot/crystal_shards/file_fetcher"
require "dependabot/crystal_shards/file_parser"
require "dependabot/crystal_shards/update_checker"
require "dependabot/crystal_shards/file_updater"
require "dependabot/crystal_shards/metadata_finder"
require "dependabot/crystal_shards/version"
require "dependabot/crystal_shards/requirement"
require "dependabot/crystal_shards/native_helpers"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("crystal_shards", name: "crystal", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "crystal_shards",
  lambda do |groups|
    return true if groups.empty?

    groups.include?("dependencies")
  end
)
