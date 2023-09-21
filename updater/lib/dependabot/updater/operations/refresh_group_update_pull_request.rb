# typed: false
# frozen_string_literal: true

require "dependabot/updater/group_update_creation"

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
        include GroupUpdateCreation

        def self.applies_to?(job:)
          return false if job.security_updates_only?
          # If we haven't been given metadata about the dependencies present
          # in the pull request and the Dependency Group that originally created
          # it, this strategy cannot act.
          return false unless job.dependencies&.any?
          return false unless job.dependency_group_to_refresh

          job.updating_a_pull_request? && Dependabot::Experiments.enabled?(:grouped_updates_prototype)
        end

        def self.tag_name
          :update_version_group_pr
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
        end

        def perform
          # This guards against any jobs being performed where the data is malformed, this should not happen unless
          # there was is defect in the service and we emitted a payload where the job and configuration data objects
          # were out of sync.
          unless dependency_snapshot.job_group
            Dependabot.logger.warn(
              "The '#{job.dependency_group_to_refresh || 'unknown'}' group has been removed from the update config."
            )

            service.capture_exception(
              error: DependabotError.new("Attempted to refresh a missing group."),
              job: job
            )
            return
          end

          Dependabot.logger.info("Starting PR update job for #{job.source.repo}")

          if dependency_snapshot.job_group.dependencies.empty?
            # If the group is empty that means any Dependencies that did match this group
            # have been removed from the project or are no longer allowed by the config.
            #
            # Let's warn that the group is empty and then signal the PR should be closed
            # so users are informed this group is no longer actionable by Dependabot.
            warn_group_is_empty(dependency_snapshot.job_group)
            close_pull_request(reason: :dependency_group_empty)
          else
            Dependabot.logger.info("Updating the '#{dependency_snapshot.job_group.name}' group")

            dependency_change = compile_all_dependency_changes_for(dependency_snapshot.job_group)

            upsert_pull_request_with_error_handling(dependency_change)
          end
        end

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler

        def upsert_pull_request_with_error_handling(dependency_change)
          if dependency_change.updated_dependencies.any?
            upsert_pull_request(dependency_change)
          else
            Dependabot.logger.info("Dependencies are up to date, closing existing Pull Request")
            close_pull_request(reason: :up_to_date)
          end
        rescue StandardError => e
          error_handler.handle_job_error(error: e, group: job_group)
        end

        # Having created the dependency_change, we need to determine the right strategy to apply it to the project:
        # - Replace existing PR if the dependencies involved have changed
        # - Update the existing PR if the dependencies and the target versions remain the same
        # - Supersede the existing PR if the dependencies are the same but the target versions have changed
        def upsert_pull_request(dependency_change)
          if dependency_change.should_replace_existing_pr?
            Dependabot.logger.info("Dependencies have changed, closing existing Pull Request")
            close_pull_request(reason: :dependencies_changed)
            Dependabot.logger.info("Creating a new pull request for '#{dependency_snapshot.job_group.name}'")
            service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
          elsif dependency_change.matches_existing_pr?
            Dependabot.logger.info("Updating pull request for '#{dependency_snapshot.job_group.name}'")
            service.update_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
          else
            # If the changes do not match an existing PR, then we should open a new pull request and leave it to
            # the backend to close the existing pull request with a comment that it has been superseded.
            Dependabot.logger.info("Target versions have changed, existing Pull Request should be superseded")
            Dependabot.logger.info("Creating a new pull request for '#{dependency_snapshot.job_group.name}'")
            service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
          end
        end

        def close_pull_request(reason:)
          reason_string = reason.to_s.tr("_", " ")
          Dependabot.logger.info(
            "Telling backend to close pull request for the " \
            "#{dependency_snapshot.job_group.name} group " \
            "(#{job.dependencies.join(', ')}) - #{reason_string}"
          )

          service.close_pull_request(job.dependencies, reason)
        end
      end
    end
  end
end
