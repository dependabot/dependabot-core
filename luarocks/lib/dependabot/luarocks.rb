# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/luarocks/file_fetcher"
require "dependabot/luarocks/file_parser"
require "dependabot/luarocks/update_checker"
require "dependabot/luarocks/file_updater"
require "dependabot/luarocks/metadata_finder"
require "dependabot/luarocks/version"
require "dependabot/luarocks/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("luarocks", name: "luarocks", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("luarocks", ->(_) { true })
