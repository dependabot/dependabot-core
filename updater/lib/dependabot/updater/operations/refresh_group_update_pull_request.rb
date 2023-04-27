# frozen_string_literal: true

require "dependabot/dependency_change_builder"

# This class implements our strategy for refreshing a single Pull Request which
# updates all outdated Dependencies within a specific project folder that match
# a specificed Dependency Group.
#
# Refreshing a Dependency Group pull request essentially has two outcomes, we
# either update or supersede the existing PR.
#
# To decide which strategy to use, we recompute the DependencyChange on the
# current head of the target branch and:
# - determine that all the same dependencies change to the same versions
#   - in this case we update the existing PR
# - determine that one or more dependencies are now involved or removed
#   - in this case we close the existing PR and create a new one
# - determine that all the dependencies are the same, but versions have changed
#   -in this case we close the existing PR and create a new one
module Dependabot
  class Updater
    module Operations
      class RefreshGroupUpdatePullRequest
        def self.applies_to?(job:)
          return false if job.security_updates_only?
          # If we haven't been given metadata about the dependencies present
          # in the pull request and the Dependency Group that originally created
          # it, this strategy cannot act.
          return false unless job.dependencies&.any?
          return false unless job.dependency_group_to_refresh

          job.updating_a_pull_request? && Dependabot::Experiments.enabled?(:grouped_updates_prototype)
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
        end

        def perform
          #
        end
      end
    end
  end
end
