# typed: strict
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
        extend T::Sig
        include GroupUpdateCreation

        sig { params(job: Dependabot::Job).returns(T::Boolean) }
        def self.applies_to?(job:)
          return false if job.updating_a_pull_request?
          if Dependabot::Experiments.enabled?(:grouped_security_updates_disabled) && job.security_updates_only?
            return false
          end

          if job.security_updates_only?
            return true if job.dependencies && T.must(job.dependencies).count > 1
            return true if job.dependency_groups.any? { |group| group["applies-to"] == "security-updates" }

            return false
          end

          true
        end

        sig { returns(Symbol) }
        def self.tag_name
          :group_update_all_versions
        end

        sig do
          params(
            service: Dependabot::Service,
            job: Dependabot::Job,
            dependency_snapshot: Dependabot::DependencySnapshot,
            error_handler: Dependabot::Updater::ErrorHandler
          ).void
        end
        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          @dependencies_handled = T.let(Set.new, T::Set[String])
        end

        sig { void }
        def perform
          run_grouped_dependency_updates if dependency_snapshot.groups.any?
          run_ungrouped_dependency_updates
        end

        private

        sig { returns(Dependabot::Job) }
        attr_reader :job

        sig { returns(Dependabot::Service) }
        attr_reader :service

        sig { returns(Dependabot::DependencySnapshot) }
        attr_reader :dependency_snapshot

        sig { returns(Dependabot::Updater::ErrorHandler) }
        attr_reader :error_handler

        sig { returns(T::Array[Dependabot::DependencyGroup]) }
        def run_grouped_dependency_updates
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
              dependency_snapshot.mark_group_handled(group)
              next
            end

            group
          end

          groups_without_pr.each do |group|
            dependency_change = run_grouped_update_for(group)
            # The update failed, add the suspected dependencies to the handled list so they don't update individually.
            dependency_snapshot.mark_group_handled(group) if dependency_change.nil?
          end
        end

        sig { params(group: Dependabot::DependencyGroup).returns(T.nilable(Dependabot::DependencyChange)) }
        def run_grouped_update_for(group)
          Dependabot::Updater::Operations::CreateGroupUpdatePullRequest.new(
            service: service,
            job: job,
            dependency_snapshot: dependency_snapshot,
            error_handler: error_handler,
            group: group
          ).perform
        end

        sig { void }
        def run_ungrouped_dependency_updates
          directories.each do |directory|
            job.source.directory = directory
            dependency_snapshot.current_directory = directory
            next unless dependency_snapshot.dependencies.any?

            if dependency_snapshot.ungrouped_dependencies.empty?
              Dependabot.logger.info("Found no dependencies to update after filtering allowed updates in #{directory}")
              next
            end

            Dependabot::Updater::Operations::UpdateAllVersions.new(
              service: service,
              job: job,
              dependency_snapshot: dependency_snapshot,
              error_handler: error_handler
            ).perform
          end
        end

        sig { returns(T::Array[String]) }
        def directories
          if job.source.directories.nil?
            [T.must(job.source.directory)]
          else
            T.must(job.source.directories)
          end
        end
      end
    end
  end
end
