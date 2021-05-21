# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/swift/package"
require "dependabot/swift/file_fetcher"
require "dependabot/swift/file_parser"
require "dependabot/swift/update_checker"
require "dependabot/swift/file_updater"
require "dependabot/swift/metadata_finder"
require "dependabot/swift/package"
require "dependabot/swift/requirement"
require "dependabot/swift/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("swift", name: "swift_package_manager", colour: "F05138")

require "dependabot/dependency"
Dependabot::Dependency.
  register_production_check("swift", ->(_) { true })
