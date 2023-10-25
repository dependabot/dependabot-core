# typed: true
# frozen_string_literal: true

require "dependabot/updater/security_update_helpers"
require "dependabot/updater/group_update_creation"
require "dependabot/updater/group_update_refreshing"

# This class implements our strategy for updating multiple, insecure dependencies
# to a secure version. We attempt to make the smallest version update possible,
# i.e. semver patch-level increase is preferred over minor-level increase.
module Dependabot
  class Updater
    module Operations
      class RefreshGroupSecurityUpdatePullRequest
        include SecurityUpdateHelpers
        include GroupUpdateCreation
        include GroupUpdateRefreshing

        def self.applies_to?(job:)
          # If we haven't been given data for the vulnerable dependency,
          # this strategy cannot act.
          return false unless job.dependencies&.any?
          return false unless job.security_updates_only?
          return false unless job.dependencies.count > 1

          job.updating_a_pull_request?
        end

        def self.tag_name
          :update_security_group_pr
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
        end

        def perform
          Dependabot.logger.info("Starting security update job for #{job.source.repo}")

          target_dependencies = dependency_snapshot.job_dependencies

          if target_dependencies.empty?
            record_security_update_dependency_not_found
          else
            # make a temporary fake group to use the existing logic
            group = Dependabot::DependencyGroup.new(
              name: "#{job.package_manager} at #{job.source.directory || '/'} security update",
              rules: {
                "patterns" => "*" # The grouping is more dictated by the dependencies passed in.
              }
            )
            target_dependencies.each do |dep|
              group.dependencies << dep
            end

            dependency_change = compile_all_dependency_changes_for(group)

            if dependency_change.updated_dependencies.any?
              upsert_pull_request_with_error_handling(dependency_change, group)
            else
              Dependabot.logger.info("Nothing to update for Dependency Group: '#{group.name}'")
            end

            dependency_change
          end
        end

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler,
                    :created_pull_requests
      end
    end
  end
end
