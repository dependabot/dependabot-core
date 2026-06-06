# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/prek/file_fetcher"
require "dependabot/prek/file_parser"
require "dependabot/prek/update_checker"
require "dependabot/prek/file_updater"
require "dependabot/prek/metadata_finder"
require "dependabot/prek/version"
require "dependabot/prek/requirement"
require "dependabot/pre_commit/comment_version_helper"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("prek", name: "prek", colour: "000000")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("prek", ->(_) { true })

# Register a humanized previous version builder for prek that extracts the
# version from the comment when using the frozen SHA format
# (e.g. rev = "<sha>"  # frozen: v2.2.1). prek reuses pre-commit's comment
# format, so the same pattern applies.
Dependabot::Dependency.register_humanized_previous_version_builder(
  "prek",
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
