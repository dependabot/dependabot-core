# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require 'dependabot/cocoapods/file_fetcher'
require 'dependabot/cocoapods/file_parser'
require 'dependabot/cocoapods/update_checker'
require 'dependabot/cocoapods/file_updater'
require 'dependabot/cocoapods/metadata_finder'
require 'dependabot/cocoapods/requirement'
require 'dependabot/cocoapods/version'

require 'dependabot/pull_request_creator/labeler'
Dependabot::PullRequestCreator::Labeler
  .register_label_details('cocoapods', name: 'cocoapods', colour: 'F40E07')

require 'dependabot/dependency'
Dependabot::Dependency
  .register_production_check('cocoapods', ->(_) { true })
