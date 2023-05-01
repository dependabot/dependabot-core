# frozen_string_literal: true

require "dependabot/dependency_change_builder"

# This class implements our strategy for creating a single Pull Request which
# updates all outdated Dependencies within a specific project folder.
#
# **Note:** This is currently an experimental feature which is not supported
#           in the service or as an integration point.
#
# Some limitations of the current implementation:
# - It disregards any ignore rules for sake of simplicity
# - It has no superseding logic, so every time this strategy runs for a repo
#   it will create a new Pull Request regardless of any existing, open PR
# - The concept of a 'dependency group' or 'update group' which configures which
#   dependencies should go together is stubbed out; it currently makes best
#   effort to update everything it can in one pass.
module Dependabot
  class Updater
    module Operations
      class GroupUpdateAllVersions
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
        # rubocop:disable Metrics/PerceivedComplexity
        def perform
          # FIXME: This preserves the default behavior of grouping all updates into a single PR
          # but we should figure out if this is the default behavior we want.
          register_all_dependencies_group unless job.dependency_groups&.any?

          Dependabot.logger.info("Starting grouped update job for #{job.source.repo}")

          dependency_snapshot.groups.each do |_group_hash, group|
            Dependabot.logger.info("Starting update group for '#{group.name}'")

            next if pr_exists_for_dependency_group?(group)

            dependency_change = compile_all_dependency_changes_for(group)

            if dependency_change.updated_dependencies.any?
              Dependabot.logger.info("Creating a pull request for '#{group.name}'")
              begin
                service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
              rescue StandardError => e
                # FIXME: This is a workround for not having a single Dependency to report against
                #
                #        We could use all_updated_deps.first, but that could be misleading. It may
                #        make more sense to handle the dependency group as a Dependancy-ish object
                group_dependency = OpenStruct.new(name: "group-all")
                raise if ErrorHandler::RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

                error_handler.handle_dependabot_error(error: e, dependency: group_dependency)
              end
            else
              Dependabot.logger.info("Nothing to update for Dependency Group: '#{group.name}'")
            end
          end

          run_ungrouped_dependency_updates if dependency_snapshot.ungrouped_dependencies.any?
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        def dependencies
          if dependency_snapshot.dependencies.any? && dependency_snapshot.allowed_dependencies.none?
            Dependabot.logger.info("Found no dependencies to update after filtering allowed updates")
            return []
          end

          dependency_snapshot.allowed_dependencies
        end

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

        def pr_exists_for_dependency_group?(group)
          job.existing_group_pull_requests.
            each&.
            any? { |pr| pr.dig(:dependency_group, "name") == group.name }
        end

        # Returns a Dependabot::DependencyChange object that encapsulates the
        # outcome of attempting to update every dependency iteratively which
        # can be used for PR creation.
        def compile_all_dependency_changes_for(group)
          all_updated_dependencies = []
          updated_files = []
          dependencies.each do |dependency|
            next unless group.contains?(dependency)

            dependency_files = original_files_merged_with(updated_files)
            updated_dependencies = compile_updates_for(dependency, dependency_files)

            next unless updated_dependencies.any?

            lead_dependency = updated_dependencies.find do |dep|
              dep.name.casecmp(dependency.name).zero?
            end

            dependency_change = create_change_for(lead_dependency, updated_dependencies, dependency_files, group)

            # Move on to the next dependency using the existing files if we
            # could not create a change for any reason
            next unless dependency_change

            # FIXME: all_updated_dependencies may need to be de-duped
            #
            # To start out with, using a variant on the 'existing_pull_request'
            # logic might make sense -or- we could employ a one-and-done rule
            # where the first update to a dependency blocks subsequent changes.
            #
            # In a follow-up iteration, a 'shared workspace' could provide the
            # filtering for us assuming we iteratively make file changes for
            # each Array of dependencies in the batch and the FileUpdater tells
            # us which cannot be applied.
            all_updated_dependencies.concat(dependency_change.updated_dependencies)

            # Store the updated files for the next loop
            updated_files = dependency_change.updated_dependency_files
          end

          # Create a single Dependabot::DependencyChange that aggregates everything we've updated
          # into a single object we can pass to PR creation.
          Dependabot::DependencyChange.new(
            job: job,
            updated_dependencies: all_updated_dependencies,
            updated_dependency_files: updated_files,
            dependency_group: group
          )
        end

        # This method generates a DependencyChange from the current files and
        # list of dependencies to be updated
        #
        # This method **must** return false in the event of an error
        def create_change_for(lead_dependency, updated_dependencies, dependency_files, dependency_group)
          Dependabot::DependencyChangeBuilder.create_from(
            job: job,
            dependency_files: dependency_files,
            updated_dependencies: updated_dependencies,
            change_source: dependency_group
          )
        rescue Dependabot::InconsistentRegistryResponse => e
          error_handler.log_error(
            dependency: lead_dependency,
            error: e,
            error_type: "inconsistent_registry_response",
            error_detail: e.message
          )

          false
        rescue StandardError => e
          raise if ErrorHandler::RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

          error_handler.handle_dependabot_error(error: e, dependency: lead_dependency)

          false
        end

        # This method determines which dependencies must change given a target
        # 'lead' dependency we want to update.
        #
        # This may return more than 1 dependency since the ecosystem-specific
        # tooling may find collaborators which need to be updated in lock-step.
        #
        # This method **must** must return an Array when it errors
        #
        def compile_updates_for(dependency, dependency_files) # rubocop:disable Metrics/MethodLength
          checker = update_checker_for(dependency, dependency_files, raise_on_ignored: raise_on_ignored?(dependency))

          log_checking_for_update(dependency)

          return [] if all_versions_ignored?(dependency, checker)

          if checker.up_to_date?
            log_up_to_date(dependency)
            return []
          end

          requirements_to_unlock = requirements_to_unlock(checker)
          log_requirements_for_update(requirements_to_unlock, checker)

          if requirements_to_unlock == :update_not_possible
            Dependabot.logger.info(
              "No update possible for #{dependency.name} #{dependency.version}"
            )
            return []
          end

          updated_deps = checker.updated_dependencies(
            requirements_to_unlock: requirements_to_unlock
          )

          if peer_dependency_should_update_instead?(checker.dependency.name, updated_deps)
            Dependabot.logger.info(
              "No update possible for #{dependency.name} #{dependency.version} (peer dependency can be updated)"
            )
            return []
          end

          updated_deps
        rescue Dependabot::InconsistentRegistryResponse => e
          error_handler.log_error(
            dependency: dependency,
            error: e,
            error_type: "inconsistent_registry_response",
            error_detail: e.message
          )
          [] # return an empty set
        rescue StandardError => e
          error_handler.handle_dependabot_error(error: e, dependency: dependency)
          [] # return an empty set
        end

        # This method is responsible for superimposing a set of file changes on
        # top of the snapshot we started with. This ensures that every update
        # has the full file list, not just those which have been modified so far
        def original_files_merged_with(updated_files)
          return dependency_snapshot.dependency_files if updated_files.empty?

          dependency_snapshot.dependency_files.map do |original_file|
            original_file = updated_files.find { |f| f.path == original_file.path } || original_file
          end
        end

        def log_up_to_date(dependency)
          Dependabot.logger.info(
            "No update needed for #{dependency.name} #{dependency.version}"
          )
        end

        def raise_on_ignored?(dependency)
          job.ignore_conditions_for(dependency).any?
        end

        def update_checker_for(dependency, dependency_files, raise_on_ignored:)
          Dependabot::UpdateCheckers.for_package_manager(job.package_manager).new(
            dependency: dependency,
            dependency_files: dependency_files,
            repo_contents_path: job.repo_contents_path,
            credentials: job.credentials,
            ignored_versions: job.ignore_conditions_for(dependency),
            security_advisories: [], # FIXME: Version updates do not use advisory data for now
            raise_on_ignored: raise_on_ignored,
            requirements_update_strategy: job.requirements_update_strategy,
            options: job.experiments
          )
        end

        def log_checking_for_update(dependency)
          Dependabot.logger.info(
            "Checking if #{dependency.name} #{dependency.version} needs updating"
          )
          job.log_ignore_conditions_for(dependency)
        end

        def all_versions_ignored?(dependency, checker)
          Dependabot.logger.info("Latest version is #{checker.latest_version}")
          false
        rescue Dependabot::AllVersionsIgnored
          Dependabot.logger.info("All updates for #{dependency.name} were ignored")
          true
        end

        def requirements_to_unlock(checker)
          if job.lockfile_only? || !checker.requirements_unlocked_or_can_be?
            if checker.can_update?(requirements_to_unlock: :none) then :none
            else
              :update_not_possible
            end
          elsif checker.can_update?(requirements_to_unlock: :own) then :own
          elsif checker.can_update?(requirements_to_unlock: :all) then :all
          else
            :update_not_possible
          end
        end

        def log_requirements_for_update(requirements_to_unlock, checker)
          Dependabot.logger.info("Requirements to unlock #{requirements_to_unlock}")

          return unless checker.respond_to?(:requirements_update_strategy)

          Dependabot.logger.info(
            "Requirements update strategy #{checker.requirements_update_strategy}"
          )
        end

        # If a version update for a peer dependency is possible we should
        # defer to the PR that will be created for it to avoid duplicate PRs.
        def peer_dependency_should_update_instead?(dependency_name, updated_deps)
          updated_deps.
            reject { |dep| dep.name == dependency_name }.
            any? do |dep|
              original_peer_dep = ::Dependabot::Dependency.new(
                name: dep.name,
                version: dep.previous_version,
                requirements: dep.previous_requirements,
                package_manager: dep.package_manager
              )
              update_checker_for(original_peer_dep, raise_on_ignored: false).
                can_update?(requirements_to_unlock: :own)
            end
        end
      end
    end
  end
end
