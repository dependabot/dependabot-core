# typed: strong
# frozen_string_literal: true

require "dependabot/updater/group_update_creation"
require "dependabot/updater/group_dependency_selector"
require "sorbet-runtime"

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
        extend T::Sig
        include GroupUpdateCreation

        # We do not invoke this class directly for any jobs, so let's return false in the event this
        # check is called.
        sig { params(_job: Dependabot::Job).returns(T::Boolean) }
        def self.applies_to?(_job:)
          false
        end

        sig { returns(Symbol) }
        def self.tag_name
          :create_version_group_pr
        end

        # Since this class is not invoked generically based on the job definition, this class accepts a `group` argument
        # which is expected to be a prepopulated DependencyGroup object.
        sig do
          params(
            service: Dependabot::Service,
            job: Dependabot::Job,
            dependency_snapshot: Dependabot::DependencySnapshot,
            error_handler: ErrorHandler,
            group: Dependabot::DependencyGroup
          ).void
        end
        def initialize(service:, job:, dependency_snapshot:, error_handler:, group:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          @group = group
        end

        # rubocop:disable Metrics/AbcSize
        sig { returns(T.nilable(Dependabot::DependencyChange)) }
        def perform
          if group.dependencies.empty?
            warn_group_is_empty(group)
            return nil
          end

          Dependabot.logger.info("Starting update group for '#{group.name}'")

          if dependency_change&.updated_dependencies&.any?
            Dependabot.logger.info("Creating a pull request for '#{group.name}'")

            # Report any failed dependency updates before creating the PR
            if Dependabot::Experiments.enabled?(:enhanced_grouped_security_error_reporting)
              report_failed_dependency_updates_for_security_updates
            end

            begin
              service.create_pull_request(T.must(dependency_change), dependency_snapshot.base_commit_sha)
            rescue StandardError => e
              error_handler.handle_job_error(error: e, dependency_group: group)
            ensure
              service.record_ecosystem_meta(dependency_snapshot.ecosystem)
              service.record_cooldown_meta(job)
            end
          else
            Dependabot.logger.info("Nothing to update for Dependency Group: '#{group.name}'")

            # If there are no updates, we still want to report them as failed updates
            if Dependabot::Experiments.enabled?(:enhanced_grouped_security_error_reporting)
              report_failed_dependency_updates_for_security_updates
            end
          end

          dependency_change
        end
        # rubocop:enable Metrics/AbcSize

        private

        sig { returns(Dependabot::Job) }
        attr_reader :job

        sig { override.returns(Dependabot::Service) }
        attr_reader :service

        sig { returns(Dependabot::DependencySnapshot) }
        attr_reader :dependency_snapshot

        sig { returns(Dependabot::Updater::ErrorHandler) }
        attr_reader :error_handler

        sig { returns(Dependabot::DependencyGroup) }
        attr_reader :group

        sig { returns(T.nilable(Dependabot::DependencyChange)) }
        def dependency_change
          return @dependency_change if defined?(@dependency_change)

          if job.source.directories.nil?
            @dependency_change = compile_all_dependency_changes_for(group)
          else
            dependency_changes = T.must(job.source.directories).filter_map do |directory|
              job.source.directory = directory
              dependency_snapshot.current_directory = directory
              compile_all_dependency_changes_for(group)
            end

            # merge the changes together into one
            dependency_change = T.let(T.must(dependency_changes.first), Dependabot::DependencyChange)
            dependency_change.merge_changes!(T.must(dependency_changes[1..-1])) if dependency_changes.count > 1
            @dependency_change = T.let(dependency_change, T.nilable(Dependabot::DependencyChange))
          end

          # Apply GroupDependencySelector filtering to ensure only group-eligible dependencies
          if @dependency_change
            selector = Dependabot::Updater::GroupDependencySelector.new(
              group: group,
              dependency_snapshot: dependency_snapshot
            )
            selector.filter_to_group!(@dependency_change)
          end

          @dependency_change
        end

        sig { void }
        def report_failed_dependency_updates_for_security_updates
          # Only report failed updates if the group applies to security updates
          return unless job.security_updates_only?

          original_dependencies = group.dependencies
          updated_dependency_names = dependency_change&.updated_dependencies&.map(&:name) || []

          failed_dependencies = original_dependencies.reject do |dep|
            updated_dependency_names.include?(dep.name)
          end

          # Filter out dependencies that were already handled (i.e., had errors reported during processing)
          unhandled_failed_dependencies = failed_dependencies.reject do |dep|
            dependency_snapshot.handled_dependencies.include?(dep.name)
          end

          unhandled_failed_dependencies.each do |failed_dependency|
            error_handler.handle_dependency_error(
              error: Dependabot::DependabotError.new(
                "Security update failed for #{failed_dependency.name} #{failed_dependency.version}"
              ),
              dependency: failed_dependency,
              dependency_group: group
            )
          end
        end
      end
    end
  end
end
