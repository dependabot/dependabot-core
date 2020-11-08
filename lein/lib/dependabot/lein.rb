# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.

# Core
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders"
require "dependabot/pull_request_creator/labeler"
require "dependabot/update_checkers"
require "dependabot/utils"

# Lein
require "dependabot/lein/file_fetcher"
require "dependabot/lein/file_parser"
require "dependabot/lein/file_updater"

# Maven
require "dependabot/maven/metadata_finder"
require "dependabot/maven/requirement"
require "dependabot/maven/update_checker"
require "dependabot/maven/version"

Dependabot::Utils.register_requirement_class("lein", Dependabot::Maven::Requirement)
Dependabot::Utils.register_version_class("lein", Dependabot::Maven::Version)

Dependabot::UpdateCheckers.register("lein", Dependabot::Maven::UpdateChecker)
Dependabot::FileParsers.register("lein", Dependabot::Lein::FileParser)

Dependabot::Dependency.register_production_check("lein", ->(_) { true })
Dependabot::MetadataFinders.register("lein", Dependabot::Maven::MetadataFinder)

Dependabot::PullRequestCreator::Labeler.register_label_details(
  "lein",
  name: "clojure",
  colour: "db5855"
)
