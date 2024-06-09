# typed: true
# frozen_string_literal: true

require "dependabot/updater/group_update_creation"

# This class implements our strategy for creating a single Pull Request which
# updates all outdated Dependencies within a specific project folder that match
# a specified Dependency Group.
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

        attr_reader :job
        attr_reader :service
        attr_reader :dependency_snapshot
        attr_reader :error_handler
        attr_reader :group

        def dependency_change
          return @dependency_change if defined?(@dependency_change)

          if job.source.directories.nil?
            @dependency_change = compile_all_dependency_changes_for(group)
          else
            dependency_changes = job.source.directories.filter_map do |directory|
              job.source.directory = directory
              dependency_snapshot.current_directory = directory
              compile_all_dependency_changes_for(group)
            end

            # merge the changes together into one
            @dependency_change = dependency_changes.first
            @dependency_change.merge_changes!(dependency_changes[1..-1]) if dependency_changes.count > 1
            @dependency_change
          end
        end
      end
    end
  end
end
