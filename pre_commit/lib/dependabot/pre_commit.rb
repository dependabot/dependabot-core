# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/pre_commit/file_fetcher"
require "dependabot/pre_commit/file_parser"
require "dependabot/pre_commit/update_checker"
require "dependabot/pre_commit/file_updater"
require "dependabot/pre_commit/metadata_finder"
require "dependabot/pre_commit/version"
require "dependabot/pre_commit/requirement"
require "dependabot/pre_commit/helpers"
require "dependabot/pre_commit/comment_version_helper"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("pre_commit", name: "pre_commit", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("pre_commit", ->(_) { true })

# Register a humanized previous version builder for pre_commit that extracts
# the version from the comment when using frozen SHA format (e.g., rev: <sha> # v2.2.1)
Dependabot::Dependency.register_humanized_previous_version_builder(
  "pre_commit",
  lambda { |dep|
    previous_reqs = dep.previous_requirements
    return nil unless previous_reqs

    comment = previous_reqs
              .filter_map { |r| r.dig(:metadata, :comment) }
              .first
    return nil unless comment

    match = comment.match(Dependabot::PreCommit::CommentVersionHelper::COMMENT_VERSION_PATTERN)
    match&.[](0)
  }
)
