# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/puppet/file_fetcher"
require "dependabot/puppet/file_parser"
require "dependabot/puppet/update_checker"
require "dependabot/puppet/file_updater"
require "dependabot/puppet/metadata_finder"
require "dependabot/puppet/requirement"
require "dependabot/puppet/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("puppet", name: "puppet", colour: "ffae1a")

require "dependabot/dependency"
Dependabot::Dependency.
  register_production_check("puppet", ->(_) { true })
