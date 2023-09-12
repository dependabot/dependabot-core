# typed: false
# frozen_string_literal: true

require "dependabot/updater/group_update_creation"

# This class implements our strategy for creating a single Pull Request which
# updates all outdated Dependencies within a specific project folder that match
# a specificed Dependency Group.
#
# This will always post a new Pull Request to Dependabot API and does not check
# to see if any exists for the group or any of the dependencies involved.
#
module Dependabot
  class Updater
    module Operations
      class CreateGroupUpdatePullRequest
        include GroupUpdateCreation

        # We do not invoke this class directly for any jobs, so let's return false in the event this
        # check is called.
        def self.applies_to?(*)
          false
        end

        def self.tag_name
          :create_version_group_pr
        end

        # Since this class is not invoked generically based on the job definition, this class accepts a `group` argument
        # which is expected to be a prepopulated DependencyGroup object.
        def initialize(service:, job:, dependency_snapshot:, error_handler:, group:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          @group = group
        end

        def perform
          return warn_group_is_empty(group) if group.dependencies.empty?

          Dependabot.logger.info("Starting update group for '#{group.name}'")

          dependency_change = compile_all_dependency_changes_for(group)

          if dependency_change.updated_dependencies.any?
            Dependabot.logger.info("Creating a pull request for '#{group.name}'")
            begin
              service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
            rescue StandardError => e
              error_handler.handle_job_error(error: e, dependency_group: group)
            end
          else
            Dependabot.logger.info("Nothing to update for Dependency Group: '#{group.name}'")
          end

          dependency_change
        end

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler,
                    :group
      end
    end
  end
end
