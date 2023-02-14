# frozen_string_literal: true

# This class is a variation on the Strangler Pattern which the Updater#run
# method delegates to when the `prototype_grouped_updates` experiment is
# enabled.
#
# The goal of this is to allow us to use the existing Updater code that is
# shared but re-implement the methods that need to change _without_ jeopardising
# the Updater implementation for current users.
#
# This class is not expected to be long-lived once we have a better idea of how
# to pull apart the existing Updater into Single- and Grouped-strategy classes.
module Dependabot
  # Let's use SimpleDelegator so this class behaves like Dependabot::Updater
  # unless we override it.
  class ExperimentalGroupedUpdater < SimpleDelegator
    def run_grouped
      if job.updating_a_pull_request?
        raise Dependabot::NotImplemented,
              "Grouped updates do not currently support rebasing."
      end

      logger_info("[Experimental] Starting grouped update job for #{job.source.repo}")
      # We should log the rule being executed, let's just hard-code wildcard for now
      # since the prototype makes best-effort to do everything in one pass.
      logger_info("Starting batch for Group Rule: '*'")
      update_batch = dependencies.each_with_object({}) do |dep, batch|
        updated_deps = compile_updates_for(dep)
        batch[dep.name] = updated_deps if updated_deps
      end
      if update_batch.any?
        update_files_and_create_pull_request(update_batch)
      else
        logger_info("Nothing to update for Group Rule: '*'")
      end
    end
    alias run run_grouped # Override the base run implementation

    private

    # We should allow the rescue in Dependabot::Updater#run to handle errors and avoid trapping them ourselves in case
    # it results in deviating from shared behaviour. This is a safety-catch to stop that happening by accident and fail
    # tests if we override something without thinking carefully about how it should raise.
    def handle_dependabot_error(_error:, _dependency:)
      raise NoMethodError, "#{__method__} is not implemented by the delegator, call __getobj__.#{__method__} instead."
    end

    # This method decomposes Updater#check_and_create_pull_request to just compile
    # rubocop:disable Metrics/MethodLength
    def compile_updates_for(dependency)
      checker = update_checker_for(dependency, raise_on_ignored: raise_on_ignored?(dependency))

      log_checking_for_update(dependency)

      # FIXME: Prototype grouped updates do not interact with the ignore list
      # return if all_versions_ignored?(dependency, checker)

      # FIXME: Security-only updates are not supported for grouped updates yet
      #
      # BEGIN: Security-only updates checks
      # # If the dependency isn't vulnerable or we can't know for sure we won't be
      # # able to know if the updated dependency fixes any advisories
      # if job.security_updates_only?
      #   unless checker.vulnerable?
      #     # The current dependency isn't vulnerable if the version is correct and
      #     # can be matched against the advisories affected versions
      #     if checker.version_class.correct?(checker.dependency.version)
      #       return record_security_update_not_needed_error(checker)
      #     end

      #     return record_dependency_file_not_supported_error(checker)
      #   end
      #   return record_security_update_ignored(checker) unless job.allowed_update?(dependency)
      # end
      # if checker.up_to_date?
      #   # The current version is still vulnerable and  Dependabot can't find a
      #   # published or compatible non-vulnerable version, this can happen if the
      #   # fixed version hasn't been published yet or the published version isn't
      #   # compatible with the current enviroment (e.g. python version) or
      #   # version (uses a different version suffix for gradle/maven)
      #   return record_security_update_not_found(checker) if job.security_updates_only?

      #   return log_up_to_date(dependency)
      # end
      # END: Security-only updates checks
      return log_up_to_date(dependency) if checker.up_to_date? # retained from above block

      if pr_exists_for_latest_version?(checker)
        # FIXME: Security-only updates are not supported for grouped updates yet
        # record_pull_request_exists_for_latest_version(checker) if job.security_updates_only?
        return logger_info(
          "Pull request already exists for #{checker.dependency.name} " \
          "with latest version #{checker.latest_version}"
        )
      end

      requirements_to_unlock = requirements_to_unlock(checker)
      log_requirements_for_update(requirements_to_unlock, checker)

      if requirements_to_unlock == :update_not_possible
        # FIXME: Security-only updates are not supported for grouped updates yet
        # return record_security_update_not_possible_error(checker) if job.security_updates_only? && job.dependencies

        return logger_info(
          "No update possible for #{dependency.name} #{dependency.version}"
        )
      end

      updated_deps = checker.updated_dependencies(
        requirements_to_unlock: requirements_to_unlock
      )

      # FIXME: Security-only updates are not supported for grouped updates yet
      # # Prevent updates that don't end up fixing any security advisories,
      # # blocking any updates where dependabot-core updates to a vulnerable
      # # version. This happens for npm/yarn subdendencies where Dependabot has no
      # # control over the target version. Related issue:
      # # https://github.com/github/dependabot-api/issues/905
      # if job.security_updates_only? &&
      #    updated_deps.none? { |d| job.security_fix?(d) }
      #   return record_security_update_not_possible_error(checker)
      # end

      # FIXME: Prototype grouped updates do not need to check for existing PRs
      #        at this stage as we haven't defined their mutual exclusivity
      #        requirements yet.
      #
      #        The caveat is that `existing_pull_request` does two things:
      #          - Check `job.existing_pull_requests`` for PRs created by
      #            Dependabot outside the current job at some point in the past
      #          - Check the `created_pull_request` set for PRs created earlier
      #            in the previous job process
      #
      #        For grouped updates, this first should be trivial but distinct
      #        from existing behaviour; we should prefer to update an existing,
      #        unmerged PR for the given group.
      #
      #        The second initially seems like it does not apply as a process
      #        should only PR each group once but it is possible we could update
      #        a dependency that falls within a group rule _individually_ or as
      #        part of another group.
      #
      #        Solving the overlap/exclusivity strateg(y|ies) we want to support
      #        is out of scope at this stage, so let's bypass for now.
      #
      # BEGIN: Existing Pull Request Checks
      # if (existing_pr = existing_pull_request(updated_deps))
      #   # Create a update job error to prevent dependabot-api from creating a
      #   # update_not_possible error, this is likely caused by a update job retry
      #   # so should be invisible to users (as the first job completed with a pull
      #   # request)
      #   record_pull_request_exists_for_security_update(existing_pr) if job.security_updates_only?

      #   deps = existing_pr.map do |dep|
      #     if dep.fetch("dependency-removed", false)
      #       "#{dep.fetch('dependency-name')}@removed"
      #     else
      #       "#{dep.fetch('dependency-name')}@#{dep.fetch('dependency-version')}"
      #     end
      #   end

      #   return logger_info(
      #     "Pull request already exists for #{deps.join(', ')}"
      #   )
      # end
      # END: Existing Pull Request Checks

      if peer_dependency_should_update_instead?(checker.dependency.name, updated_deps)
        return logger_info(
          "No update possible for #{dependency.name} #{dependency.version} " \
          "(peer dependency can be updated)"
        )
      end
      filter_unrelated_and_unchanged(updated_deps, checker)
    # FIXME: This rescue logic is pulled in from Updater#check_and_create_pr_with_error_handling
    #        and duplicated in update_files_and_create_pull_request.
    #
    #        It isn't completely intuitive which parts of this logic belong to the
    #        "check" and which parts belong to the "create", but it should be tried
    #        out in a way that the "dependency" it reports is less of a guess for
    #        groups -or- we need to implement new error types for Grouped Pull Requests
    rescue Dependabot::InconsistentRegistryResponse => e
      log_error(
        dependency: dependency,
        error: e,
        error_type: "inconsistent_registry_response",
        error_detail: e.message
      )
      nil # Return nothing
    rescue StandardError => e
      raise if Dependabot::Updater::RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

      __getobj__.handle_dependabot_error(error: e, dependency: dependency)
      nil # Return nothing
    end
    # rubocop:enable Metrics/MethodLength

    def filter_unrelated_and_unchanged(updated_dependencies, checker)
      updated_dependencies.reject do |d|
        next false if d.name == checker.dependency.name
        next true if d.top_level? && d.requirements == d.previous_requirements

        d.version == d.previous_version
      end
    end

    def update_files_and_create_pull_request(update_batch)
      # FIXME: This is a workround for not having a single Dependency to report against
      #
      #        We could use update_batch.values.first, but it might make more
      #        sense to report dependency || group for the error types involved
      #        so the problem is correctly attributed to the update creation
      #        as opposed to checking any one dependency.
      #
      #        Alternatively, when we use a shared workspace to build the diff iteratively
      #        we could report against the _active_ dependency in each step. At worst this
      #        might result in an off-by-one issue if we have potential for an error between
      #        loops.
      group_dependency = OpenStruct.new(name: "group-all")

      logger_info("Generated #{update_batch.count} changes")
      # FIXME: This needs to be de-duped, but it isn't clear which dupe should
      #        'win' right now in terms of version.
      #
      #        To start out with, using a variant on the 'existing_pull_request'
      #        logic might make sense -or- we could employ a one-and-done rule
      #        where the first update to a dependency blocks subsequent changes.
      #
      #        In a follow-up iteration, a 'shared workspace' could provide the
      #        filtering for us assuming we iteratively make file changes for
      #        each Array of dependencies in the batch and the FileUpdater tells
      #        us which cannot be applied.
      all_updated_deps = update_batch.values.flatten
      logger_info("Updated #{all_updated_deps.count} dependencies")
      updated_files = generate_dependency_files_for(all_updated_deps)

      create_pull_request(all_updated_deps, updated_files, pr_message(all_updated_deps, updated_files))
    # FIXME: This rescue logic is pulled in from Updater#check_and_create_pr_with_error_handling
    #        and duplicated in update_files_and_create_pull_request.
    #
    #        It isn't completely intuitive which parts of this logic belong to the
    #        "check" and which parts belong to the "create", but it should be teased
    #        out in a way that the "dependency" it reports is less of a guess for
    #        groups -or- we need to implement new error types for Grouped Pull Requests
    rescue Dependabot::InconsistentRegistryResponse => e
      log_error(
        dependency: group_dependency,
        error: e,
        error_type: "inconsistent_registry_response",
        error_detail: e.message
      )
    rescue StandardError => e
      raise if Dependabot::Updater::RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

      __getobj__.handle_dependabot_error(error: e, dependency: group_dependency)
    end

    # Override the checker initialisation to skip configuration we don't use right now
    #
    # FIXME: Prototype grouped updates do not interact with the ignore list
    # FIXME: Prototype grouped updates to not interact with advisory data
    def update_checker_for(dependency, raise_on_ignored:)
      Dependabot::UpdateCheckers.for_package_manager(job.package_manager).new(
        dependency: dependency,
        dependency_files: dependency_files,
        repo_contents_path: repo_contents_path,
        credentials: credentials,
        ignored_versions: [],
        security_advisories: [],
        raise_on_ignored: raise_on_ignored,
        requirements_update_strategy: job.requirements_update_strategy,
        options: job.experiments
      )
    end
  end
end
