# frozen_string_literal: true

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

          Dependabot::Experiments.enabled?(:grouped_updates_prototype)
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

        # rubocop:disable Metrics/AbcSize
        def perform
          # FIXME: This preserves the default behavior of grouping all updates into a single PR
          # but we should figure out if this is the default behavior we want.
          register_all_dependencies_group unless job.dependency_groups&.any?

          Dependabot.logger.info("Starting grouped update job for #{job.source.repo}")

          dependency_snapshot.groups.each do |_group_hash, group|
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

          run_ungrouped_dependency_updates if dependency_snapshot.ungrouped_dependencies.any?
        end
        # rubocop:enable Metrics/AbcSize

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler

        def register_all_dependencies_group
          all_dependencies_group = { "name" => "all-dependencies", "rules" => { "patterns" => ["*"] } }
          Dependabot::DependencyGroupEngine.register(all_dependencies_group["name"],
                                                     all_dependencies_group["rules"]["patterns"])
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
