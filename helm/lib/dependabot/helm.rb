# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/helm/file_fetcher"
require "dependabot/helm/file_parser"
require "dependabot/helm/update_checker"
require "dependabot/helm/file_updater"
require "dependabot/helm/requirement"
require "dependabot/helm/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.register_label_details("helm", name: "helm", colour: "16e2e2")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("helm", ->(_) { true })
