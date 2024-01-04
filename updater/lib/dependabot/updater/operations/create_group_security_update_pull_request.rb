# typed: true
# frozen_string_literal: true

require "dependabot/updater/security_update_helpers"
require "dependabot/updater/group_update_creation"

# This class implements our strategy for updating multiple, insecure dependencies
# to a secure version. We attempt to make the smallest version update possible,
# i.e. semver patch-level increase is preferred over minor-level increase.
module Dependabot
  class Updater
    module Operations
      class CreateGroupSecurityUpdatePullRequest
        include SecurityUpdateHelpers
        include GroupUpdateCreation

        def self.applies_to?(job:)
          return false if Dependabot::Experiments.enabled?(:grouped_security_updates_disabled)
          return false if job.updating_a_pull_request?
          # If we haven't been given data for the vulnerable dependency,
          # this strategy cannot act.
          return false unless job.dependencies&.any?

          return false unless job.security_updates_only?

          true if job.dependencies.count > 1 || (job.source.directories && job.source.directories.count > 1)
        end

        def self.tag_name
          :create_security_pr
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          # TODO: Collect @created_pull_requests on the Job object?
          @created_pull_requests = []
        end

        def perform
          Dependabot.logger.info("Starting security update job for #{job.source.repo}")
          return record_security_update_dependency_not_found if dependency_snapshot.job_dependencies.empty?

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
                    :created_pull_requests

        def group
          return @group if defined?(@group)

          # make a temporary fake group to use the existing logic
          @group = grouped_security_update_group(job)
          dependency_snapshot.job_dependencies.each do |dep|
            @group.dependencies << dep
          end
          @group
        end

        def dependency_change
          return @dependency_change if defined?(@dependency_change)

          if job.source.directories.nil?
            @dependency_change = compile_all_dependency_changes_for(group)
          else
            dependency_changes = job.source.directories.map do |directory|
              job.source.directory = directory
              # Fixes not updating because it already updated in a previous group
              dependency_snapshot.handled_dependencies.clear
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
