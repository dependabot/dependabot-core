# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.

require "dependabot/opam/file_fetcher"
require "dependabot/opam/file_parser"
require "dependabot/opam/file_updater"
require "dependabot/opam/update_checker"
require "dependabot/opam/metadata_finder"

require "dependabot/opam/version"
Dependabot::Utils.register_version_class("opam", Dependabot::Opam::Version)

require "dependabot/opam/requirement"
Dependabot::Utils.register_requirement_class("opam", Dependabot::Opam::Requirement)

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("opam", name: "ocaml", colour: "EC6813")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("opam", ->(_) { true })
