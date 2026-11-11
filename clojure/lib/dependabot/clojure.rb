# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/clojure/file_fetcher"
require "dependabot/clojure/file_parser"
require "dependabot/clojure/update_checker"
require "dependabot/clojure/file_updater"
require "dependabot/clojure/metadata_finder"
require "dependabot/clojure/version"
require "dependabot/clojure/requirement"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("clojure", name: "clojure", colour: "db5855")

# Top-level dependencies are in the "dependencies" group. Leiningen profiles,
# plugins and deps.edn aliases have their own groups and are not production.
require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "clojure",
  ->(groups) { groups.include?(Dependabot::Clojure::MAIN_GROUP) }
)
