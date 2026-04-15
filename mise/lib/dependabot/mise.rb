# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/mise/version"
require "dependabot/mise/requirement"
require "dependabot/mise/metadata_finder"
require "dependabot/mise/file_fetcher"
require "dependabot/mise/file_parser"
require "dependabot/mise/update_checker"
require "dependabot/mise/file_updater"

# 8B2252 is used as vp-c-brand-1 in mise's official website
require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("mise", name: "mise", colour: "8B2252")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("mise", ->(_) { true })

Dependabot::Utils.register_version_class("mise", Dependabot::Mise::Version)
