# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/pull_request_creator/labeler"

module Dependabot
  module Haskell
    module PullRequestCreator
      class Labeler < Dependabot::PullRequestCreator::Labeler
        # Haskell's PVP versioning goes up to `major.major.minor.patch`,
        # rather than semver's `major.minor.patch`.
        def precision
          dependencies.map do |dep|
            new_version_parts = version(dep).split(/[.+]/)
            old_version_parts = previous_version(dep)&.split(/[.+]/) || []
            all_parts = new_version_parts.first(3) + old_version_parts.first(3)
            next 0 unless all_parts.all? { |part| part.to_i.to_s == part }
            next 1 if new_version_parts[0] != old_version_parts[0]
            next 1 if new_version_parts[1] != old_version_parts[1]
            next 2 if new_version_parts[2] != old_version_parts[2]

            3
          end.min
        end
      end
    end
  end
end

Dependabot::Utils.register_requirement_class(
  "haskell",
  Dependabot::Haskell::PullRequestCreator::Labeler
)
