# frozen_string_literal: true

require "dependabot/updater/operations/update_all_versions"
require "dependabot/updater/group_update_creation"

# This class implements our strategy for creating Pull Requests for Dependency
# Groups defined for a given folder before handling any un-grouped Dependencies
# via Dependabot::Updater::Operations::UpdateAllVersions.
#
# **Note:** This is currently an experimental feature which is not supported
#           in the service or as an integration point.
#
# Some limitations of the current implementation:
# - It has no superseding logic for groups - every time this strategy runs for a
#  repo it will create a new Pull Request regardless of any existing, open PR
module Dependabot
  class Updater
    module Operations
      class GroupUpdateAllVersions
        include GroupUpdateCreation

        def self.applies_to?(job:)
          return false if job.security_updates_only?
          return false if job.updating_a_pull_request?
          return false if job.dependencies&.any?

          job.dependency_groups&.any? && Dependabot::Experiments.enabled?(:grouped_updates_prototype)
        end

        def self.tag_name
          :grouped_updates_prototype
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
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

          run_ungrouped_dependency_updates if dependency_snapshot.ungrouped_dependencies.any?
        end

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler

        def run_grouped_dependency_updates # rubocop:disable Metrics/AbcSize
          Dependabot.logger.info("Starting grouped update job for #{job.source.repo}")
          Dependabot.logger.info("Found #{dependency_snapshot.groups.count} group(s).")

          dependency_snapshot.groups.each do |_group_hash, group|
            if pr_exists_for_dependency_group?(group)
              Dependabot.logger.info("Detected existing pull request for '#{group.name}'.")
              Dependabot.logger.info(
                "Deferring creation of a new pull request. The existing pull request will update in a separate job."
              )
              next
            end

            Dependabot.logger.info("Starting update group for '#{group.name}'")

            dependency_change = compile_all_dependency_changes_for(group)

            if dependency_change.updated_dependencies.any?
              Dependabot.logger.info("Creating a pull request for '#{group.name}'")
              begin
                service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
              rescue StandardError => e
                raise if ErrorHandler::RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

                # FIXME: This will result in us reporting a the group name as a dependency name
                #
                # In future we should modify this method to accept both dependency and group
                # so the downstream error handling can tag things appropriately.
                error_handler.handle_dependabot_error(error: e, dependency: group)
              end
            else
              Dependabot.logger.info("Nothing to update for Dependency Group: '#{group.name}'")
            end
          end
        end

        def pr_exists_for_dependency_group?(group)
          job.existing_group_pull_requests&.any? { |pr| pr["dependency-group-name"] == group.name }
        end

        def run_ungrouped_dependency_updates
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
