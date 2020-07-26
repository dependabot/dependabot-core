# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/paket/file_fetcher"
require "dependabot/paket/file_parser"
require "dependabot/paket/update_checker"
require "dependabot/paket/file_updater"
require "dependabot/paket/metadata_finder"
require "dependabot/paket/requirement"
require "dependabot/paket/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("paket", name: ".NET", colour: "7121c6")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("paket", ->(_) { true })
