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
      # Establish collection
      # Do the check and diff
      dependencies.each { |dep| check_and_create_pr_with_error_handling(dep) }
      # PR everything
    end
    alias run run_grouped

    def check_and_create_pr_with_error_handling(dependency)
      check_and_create_pull_request(dependency)
    rescue Dependabot::InconsistentRegistryResponse => e
      log_error(
        dependency: dependency,
        error: e,
        error_type: "inconsistent_registry_response",
        error_detail: e.message
      )
    rescue StandardError => e
      raise if Dependabot::Updater::RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

      __getobj__.handle_dependabot_error(error: e, dependency: dependency)
    end

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/MethodLength
    def check_and_create_pull_request(dependency)
      checker = update_checker_for(dependency, raise_on_ignored: raise_on_ignored?(dependency))

      log_checking_for_update(dependency)

      return if all_versions_ignored?(dependency, checker)

      # If the dependency isn't vulnerable or we can't know for sure we won't be
      # able to know if the updated dependency fixes any advisories
      if job.security_updates_only?
        unless checker.vulnerable?
          # The current dependency isn't vulnerable if the version is correct and
          # can be matched against the advisories affected versions
          if checker.version_class.correct?(checker.dependency.version)
            return record_security_update_not_needed_error(checker)
          end

          return record_dependency_file_not_supported_error(checker)
        end
        return record_security_update_ignored(checker) unless job.allowed_update?(dependency)
      end

      if checker.up_to_date?
        # The current version is still vulnerable and  Dependabot can't find a
        # published or compatible non-vulnerable version, this can happen if the
        # fixed version hasn't been published yet or the published version isn't
        # compatible with the current enviroment (e.g. python version) or
        # version (uses a different version suffix for gradle/maven)
        return record_security_update_not_found(checker) if job.security_updates_only?

        return log_up_to_date(dependency)
      end

      if pr_exists_for_latest_version?(checker)
        record_pull_request_exists_for_latest_version(checker) if job.security_updates_only?
        return logger_info(
          "Pull request already exists for #{checker.dependency.name} " \
          "with latest version #{checker.latest_version}"
        )
      end

      requirements_to_unlock = requirements_to_unlock(checker)
      log_requirements_for_update(requirements_to_unlock, checker)

      if requirements_to_unlock == :update_not_possible
        return record_security_update_not_possible_error(checker) if job.security_updates_only? && job.dependencies

        return logger_info(
          "No update possible for #{dependency.name} #{dependency.version}"
        )
      end

      updated_deps = checker.updated_dependencies(
        requirements_to_unlock: requirements_to_unlock
      )

      # Prevent updates that don't end up fixing any security advisories,
      # blocking any updates where dependabot-core updates to a vulnerable
      # version. This happens for npm/yarn subdendencies where Dependabot has no
      # control over the target version. Related issue:
      # https://github.com/github/dependabot-api/issues/905
      if job.security_updates_only? &&
         updated_deps.none? { |d| job.security_fix?(d) }
        return record_security_update_not_possible_error(checker)
      end

      if (existing_pr = existing_pull_request(updated_deps))
        # Create a update job error to prevent dependabot-api from creating a
        # update_not_possible error, this is likely caused by a update job retry
        # so should be invisible to users (as the first job completed with a pull
        # request)
        record_pull_request_exists_for_security_update(existing_pr) if job.security_updates_only?

        deps = existing_pr.map do |dep|
          if dep.fetch("dependency-removed", false)
            "#{dep.fetch('dependency-name')}@removed"
          else
            "#{dep.fetch('dependency-name')}@#{dep.fetch('dependency-version')}"
          end
        end

        return logger_info(
          "Pull request already exists for #{deps.join(', ')}"
        )
      end

      if peer_dependency_should_update_instead?(checker.dependency.name, updated_deps)
        return logger_info(
          "No update possible for #{dependency.name} #{dependency.version} " \
          "(peer dependency can be updated)"
        )
      end

      updated_files = generate_dependency_files_for(updated_deps)
      updated_deps = updated_deps.reject do |d|
        next false if d.name == checker.dependency.name
        next true if d.top_level? && d.requirements == d.previous_requirements

        d.version == d.previous_version
      end
      create_pull_request(updated_deps, updated_files, pr_message(updated_deps, updated_files))
    end
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    private

    # We should allow the rescue in Dependabot::Updater#run to handle errors and avoid trapping them ourselves in case
    # it results in deviating from shared behaviour. This is a safety-catch to stop that happening by accident and fail
    # tests if we override something without thinking carefully about how it should raise.
    def handle_dependabot_error(_error:, _dependency:)
      raise NoMethodError, "#{__method__} is not implemented by the delegator, call __getobj__.#{__method__} instead."
    end
  end
end
