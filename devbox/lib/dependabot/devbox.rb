# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/devbox/file_fetcher"
require "dependabot/devbox/file_parser"
require "dependabot/devbox/update_checker"
require "dependabot/devbox/file_updater"
require "dependabot/devbox/metadata_finder"
require "dependabot/devbox/package/package_details_fetcher"
require "dependabot/devbox/helpers"
require "dependabot/devbox/version"
require "dependabot/devbox/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("devbox", name: "devbox", colour: "5c4ee5")

require "dependabot/dependency"
# A devbox.json declares packages for the whole environment with no dev/prod
# distinction, so every tracked package is treated as production.
Dependabot::Dependency.register_production_check("devbox", ->(_) { true })
