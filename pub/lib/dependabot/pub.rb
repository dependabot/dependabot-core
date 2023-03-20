# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/pub/file_fetcher"
require "dependabot/pub/file_parser"
require "dependabot/pub/update_checker"
require "dependabot/pub/file_updater"
require "dependabot/pub/metadata_finder"
require "dependabot/pub/requirement"
require "dependabot/pub/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("pub", name: "dart", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("pub", ->(_) { true })

require "dependabot/utils"
Dependabot::Utils.register_always_clone("pub")
