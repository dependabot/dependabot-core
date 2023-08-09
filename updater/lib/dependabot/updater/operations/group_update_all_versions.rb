# frozen_string_literal: true

require "dependabot/updater/operations/create_group_update_pull_request"
require "dependabot/updater/operations/update_all_versions"

# This class is responsible for coordinating the creation and upkeep of Pull Requests for
# a given folder's defined DependencyGroups.
#
# - If there is no Pull Request already open for a DependencyGroup, it will be delegated
#   to Dependabot::Updater::Operations::CreateGroupUpdatePullRequest.
# - If there is an open Pull Request for a DependencyGroup, it will skip over that group
#   as the service is responsible for refreshing it in a separate job.
# - Any ungrouped Dependencies will be handled individually by delegation to
#   Dependabot::Updater::Operations::UpdateAllVersions.
#
module Dependabot
  class Updater
    module Operations
      class GroupUpdateAllVersions
        def self.applies_to?(job:)
          return false if job.security_updates_only?
          return false if job.updating_a_pull_request?
          return false if job.dependencies&.any?

          job.dependency_groups&.any? && Dependabot::Experiments.enabled?(:grouped_updates_prototype)
        end

        def self.tag_name
          :group_update_all_versions
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          @all_grouped_changes = []
        end

        def perform
          if dependency_snapshot.groups.any?
            run_grouped_dependency_updates
          else
            # We shouldn't have selected this operation if no groups were defined
            # due to the rules in `::applies_to?`, but if it happens it isn't
            # enough reasons to fail the job.
            Dependabot.logger.warn(
              "No dependency groups defined!"
            )

            # We should warn our exception tracker in case this represents an
            # unexpected problem hydrating groups we have swallowed and then
            # delegate everything to run_ungrouped_dependency_updates.
            service.capture_exception(
              error: DependabotError.new("Attempted a grouped update with no groups defined."),
              job: job
            )
          end

          run_ungrouped_dependency_updates
        end

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler

        def run_grouped_dependency_updates
          Dependabot.logger.info("Starting grouped update job for #{job.source.repo}")
          Dependabot.logger.info("Found #{dependency_snapshot.groups.count} group(s).")

          dependency_snapshot.groups.each do |group|
            if pr_exists_for_dependency_group?(group)
              Dependabot.logger.info("Detected existing pull request for '#{group.name}'.")
              Dependabot.logger.info(
                "Deferring creation of a new pull request. The existing pull request will update in a separate job."
              )
              next
            end

            result = run_update_for(group)
            @all_grouped_changes += result&.updated_dependencies || []
          end
        end

        def pr_exists_for_dependency_group?(group)
          job.existing_group_pull_requests&.any? { |pr| pr["dependency-group-name"] == group.name }
        end

        def run_update_for(group)
          Dependabot::Updater::Operations::CreateGroupUpdatePullRequest.new(
            service: service,
            job: job,
            dependency_snapshot: dependency_snapshot,
            error_handler: error_handler,
            group: group
          ).perform
        end

        def run_ungrouped_dependency_updates
          dependency_snapshot.calculate_ungrouped_dependencies(@all_grouped_changes)

          Dependabot::Updater::Operations::UpdateAllVersions.new(
            service: service,
            job: job,
            dependency_snapshot: dependency_snapshot,
            error_handler: error_handler
          ).perform
        end
      end
    end
  end
end
