# frozen_string_literal: true

require "dependabot/dependency_change_builder"
require "dependabot/updater/dependency_group_change_batch"
require "dependabot/workspace"

# This module contains the methods required to build a DependencyChange for
# a single DependencyGroup.
#
# When included in an Operation it expects the following to be available:
# - job: the current Dependabot::Job object
# - dependency_snapshot: the Dependabot::DependencySnapshot of the current state
# - error_handler: a Dependabot::UpdaterErrorHandler to report any problems to
#
module Dependabot
  class Updater
    module GroupUpdateCreation
      # Returns a Dependabot::DependencyChange object that encapsulates the
      # outcome of attempting to update every dependency iteratively which
      # can be used for PR creation.
      def compile_all_dependency_changes_for(group)
        prepare_workspace

        group_changes = Dependabot::Updater::DependencyGroupChangeBatch.new(
          initial_dependency_files: dependency_snapshot.dependency_files
        )

        group.dependencies.each do |dependency|
          # Get the current state of the dependency files for use in this iteration
          dependency_files = group_changes.current_dependency_files

          # Reparse the current files
          reparsed_dependencies = dependency_file_parser(dependency_files).parse
          dependency = reparsed_dependencies.find { |d| d.name == dependency.name }

          # If the dependency can not be found in the reparsed files then it was likely removed by a previous
          # dependency update
          next if dependency.nil?

          updated_dependencies = compile_updates_for(dependency, dependency_files, group)

          next unless updated_dependencies.any?

          lead_dependency = updated_dependencies.find do |dep|
            dep.name.casecmp(dependency.name).zero?
          end

          dependency_change = create_change_for(lead_dependency, updated_dependencies, dependency_files, group)

          # Move on to the next dependency using the existing files if we
          # could not create a change for any reason
          next unless dependency_change

          # Store the updated files for the next loop
          group_changes.merge(dependency_change)
          store_changes(dependency)
        end

        # Create a single Dependabot::DependencyChange that aggregates everything we've updated
        # into a single object we can pass to PR creation.
        Dependabot::DependencyChange.new(
          job: job,
          updated_dependencies: group_changes.updated_dependencies,
          updated_dependency_files: group_changes.updated_dependency_files,
          dependency_group: group
        )
      ensure
        cleanup_workspace
      end

      def dependency_file_parser(dependency_files)
        Dependabot::FileParsers.for_package_manager(job.package_manager).new(
          dependency_files: dependency_files,
          repo_contents_path: job.repo_contents_path,
          source: job.source,
          credentials: job.credentials,
          reject_external_code: job.reject_external_code?,
          options: job.experiments
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
        error_handler.log_dependency_error(
          dependency: lead_dependency,
          error: e,
          error_type: "inconsistent_registry_response",
          error_detail: e.message
        )

        false
      rescue StandardError => e
        error_handler.handle_dependency_error(error: e, dependency: lead_dependency, dependency_group: dependency_group)

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
      def compile_updates_for(dependency, dependency_files, group) # rubocop:disable Metrics/MethodLength
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

        if peer_dependency_should_update_instead?(checker.dependency.name, dependency_files, updated_deps)
          Dependabot.logger.info(
            "No update possible for #{dependency.name} #{dependency.version} (peer dependency can be updated)"
          )
          return []
        end

        updated_deps
      rescue Dependabot::InconsistentRegistryResponse => e
        error_handler.log_dependency_error(
          dependency: dependency,
          error: e,
          error_type: "inconsistent_registry_response",
          error_detail: e.message
        )
        [] # return an empty set
      rescue StandardError => e
        error_handler.handle_dependency_error(error: e, dependency: dependency, dependency_group: group)
        [] # return an empty set
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
        if !checker.requirements_unlocked_or_can_be?
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
      def peer_dependency_should_update_instead?(dependency_name, dependency_files, updated_deps)
        updated_deps.
          reject { |dep| dep.name == dependency_name }.
          any? do |dep|
            original_peer_dep = ::Dependabot::Dependency.new(
              name: dep.name,
              version: dep.previous_version,
              requirements: dep.previous_requirements,
              package_manager: dep.package_manager
            )
            update_checker_for(original_peer_dep, dependency_files, raise_on_ignored: false).
              can_update?(requirements_to_unlock: :own)
          end
      end

      def warn_group_is_empty(group)
        Dependabot.logger.warn(
          "Skipping update group for '#{group.name}' as it does not match any allowed dependencies."
        )

        return unless Dependabot.logger.debug?

        Dependabot.logger.debug(<<~DEBUG.chomp)
          The configuration for this group is:

          #{group.to_config_yaml}
        DEBUG
      end

      def prepare_workspace
        return unless job.clone? && job.repo_contents_path

        Dependabot::Workspace.setup(
          repo_contents_path: job.repo_contents_path,
          directory: Pathname.new(job.source.directory || "/").cleanpath
        )
      end

      def store_changes(dependency)
        return unless job.clone? && job.repo_contents_path

        Dependabot::Workspace.store_change(memo: "Updating #{dependency.name}")
      end

      def cleanup_workspace
        return unless job.clone? && job.repo_contents_path

        Dependabot::Workspace.cleanup!
      end
    end
  end
end
