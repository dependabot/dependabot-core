# typed: true
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
        include GroupUpdateCreation

        def self.applies_to?(job:) # rubocop:disable Metrics/PerceivedComplexity
          return false if job.updating_a_pull_request?
          if Dependabot::Experiments.enabled?(:grouped_security_updates_disabled) && job.security_updates_only?
            return false
          end

          return true if job.source.directories && job.source.directories.count > 1

          if job.security_updates_only?
            return true if job.dependencies.count > 1
            return true if job.dependency_groups&.any? { |group| group["applies-to"] == "security-updates" }

            return false
          end

          job.dependency_groups&.any?
        end

        def self.tag_name
          :group_update_all_versions
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          @dependencies_handled = Set.new
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

        attr_reader :job
        attr_reader :service
        attr_reader :dependency_snapshot
        attr_reader :error_handler

        def run_grouped_dependency_updates # rubocop:disable Metrics/AbcSize
          Dependabot.logger.info("Starting grouped update job for #{job.source.repo}")
          Dependabot.logger.info("Found #{dependency_snapshot.groups.count} group(s).")

          # Preprocess to discover existing group PRs and add their dependencies to the handled list before processing
          # the rest of the groups. This prevents multiple PRs from being created for the same dependency.
          groups_without_pr = dependency_snapshot.groups.filter_map do |group|
            if pr_exists_for_dependency_group?(group)
              Dependabot.logger.info("Detected existing pull request for '#{group.name}'.")
              Dependabot.logger.info(
                "Deferring creation of a new pull request. The existing pull request will update in a separate job."
              )
              # add the dependencies in the group so individual updates don't try to update them
              dependency_snapshot.add_handled_dependencies(
                dependencies_in_existing_pr_for_group(group).map { |d| d["dependency-name"] }
              )
              # also add dependencies that might be in the group, as a rebase would add them;
              # this avoids individual PR creation that immediately is superseded by a group PR supersede
              dependency_snapshot.add_handled_dependencies(group.dependencies.map(&:name))
              next
            end

            group
          end

          groups_without_pr.each do |group|
            result = run_update_for(group)
            if result
              # Add the actual updated dependencies to the handled list so they don't get updated individually.
              dependency_snapshot.add_handled_dependencies(result.updated_dependencies.map(&:name))
            else
              # The update failed, add the suspected dependencies to the handled list so they don't update individually.
              dependency_snapshot.add_handled_dependencies(group.dependencies.map(&:name))
            end
          end
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
          if job.source.directories.nil?
            return if dependency_snapshot.ungrouped_dependencies.empty?

            Dependabot::Updater::Operations::UpdateAllVersions.new(
              service: service,
              job: job,
              dependency_snapshot: dependency_snapshot,
              error_handler: error_handler
            ).perform
          else
            job.source.directories.each do |directory|
              job.source.directory = directory
              dependency_snapshot.current_directory = directory
              next if dependency_snapshot.ungrouped_dependencies.empty?

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
  end
end
