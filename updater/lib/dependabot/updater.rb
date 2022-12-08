# frozen_string_literal: true

require "raven"
require "dependabot/config/ignore_condition"
require "dependabot/config/update_config"
require "dependabot/environment"
require "dependabot/experiments"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/file_updaters"
require "dependabot/logger"
require "dependabot/python"
require "dependabot/terraform"
require "dependabot/elm"
require "dependabot/docker"
require "dependabot/git_submodules"
require "dependabot/github_actions"
require "dependabot/composer"
require "dependabot/nuget"
require "dependabot/gradle"
require "dependabot/maven"
require "dependabot/hex"
require "dependabot/cargo"
require "dependabot/go_modules"
require "dependabot/npm_and_yarn"
require "dependabot/bundler"
require "dependabot/pub"

require "dependabot/security_advisory"
require "dependabot/update_checkers"
require "wildcard_matcher"

# rubocop:disable Metrics/ClassLength
module Dependabot
  class Updater
    class SubprocessFailed < StandardError
      attr_reader :raven_context

      def initialize(message, raven_context:)
        super(message)

        @raven_context = raven_context
      end
    end

    # These are errors that halt the update run and are handled in the main
    # backend. They do *not* raise a sentry.
    RUN_HALTING_ERRORS = {
      Dependabot::OutOfDisk => "out_of_disk",
      Dependabot::OutOfMemory => "out_of_memory",
      Dependabot::AllVersionsIgnored => "all_versions_ignored",
      Dependabot::UnexpectedExternalCode => "unexpected_external_code",
      Errno::ENOSPC => "out_of_disk",
      Octokit::Unauthorized => "octokit_unauthorized"
    }.freeze

    def initialize(service:, job_id:, job:, dependency_files:,
                   base_commit_sha:, repo_contents_path:)
      @service = service
      @job_id = job_id
      @job = job
      @dependency_files = dependency_files
      @base_commit_sha = base_commit_sha
      @repo_contents_path = repo_contents_path
      @errors = []
      @created_pull_requests = []
    end

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/PerceivedComplexity
    def run
      return unless job

      if job.updating_a_pull_request?
        logger_info("Starting PR update job for #{job.source.repo}")
        check_and_update_existing_pr_with_error_handling(dependencies)
      else
        logger_info("Starting update job for #{job.source.repo}")
        if ENV["UPDATER_DETERMINISTIC"]
          dependencies.each { |dep| check_and_create_pr_with_error_handling(dep) }
        else
          dependencies.shuffle.each { |dep| check_and_create_pr_with_error_handling(dep) }
        end
      end
    rescue *RUN_HALTING_ERRORS.keys => e
      if e.is_a?(Dependabot::AllVersionsIgnored) && !job.security_updates_only?
        error = StandardError.new(
          "Dependabot::AllVersionsIgnored was unexpectedly raised for a non-security update job"
        )
        error.set_backtrace(e.backtrace)
        Raven.capture_exception(error, raven_context)
        return
      end

      # OOM errors are special cased so that we stop the update run early
      error = { "error-type": RUN_HALTING_ERRORS.fetch(e.class) }
      record_error(error)
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/PerceivedComplexity

    private

    attr_accessor :errors, :created_pull_requests
    attr_reader :service, :job_id, :job, :dependency_files, :base_commit_sha,
                :repo_contents_path

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
      raise if RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

      handle_dependabot_error(error: e, dependency: dependency)
    end

    def check_and_update_existing_pr_with_error_handling(dependencies)
      dependency = dependencies.last
      check_and_update_pull_request(dependencies)
    rescue StandardError => e
      raise if RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

      handle_dependabot_error(error: e, dependency: dependency)
    end

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/MethodLength
    def check_and_update_pull_request(dependencies)
      if dependencies.count != job.dependencies.count
        close_pull_request(reason: :dependency_removed) unless errors.any?
        return
      end

      # NOTE: Prevent security only updates from turning into latest version
      # updates if the current version is no longer vulnerable. This happens
      # when a security update is applied by the user directly and the existing
      # pull request is rebased.
      if job.security_updates_only? &&
         dependencies.none? { |d| job.allowed_update?(d) }
        lead_dependency = dependencies.first
        if job.vulnerable?(lead_dependency)
          logger_info("Dependency no longer allowed to update #{lead_dependency.name} #{lead_dependency.version}")
        else
          logger_info("No longer vulnerable #{lead_dependency.name} #{lead_dependency.version}")
        end
        close_pull_request(reason: :up_to_date)
        return
      end

      # The first dependency is the "lead" dependency in a multi-dependency
      # update - i.e., the one we're trying to update.
      #
      # Note: Gradle, Maven and Nuget dependency names can be case-insensitive
      # and the dependency name in the security advisory often doesn't match
      # what users have specified in their manifest.
      lead_dep_name = job.dependencies.first.downcase
      lead_dependency = dependencies.find do |dep|
        dep.name.downcase == lead_dep_name
      end
      checker = update_checker_for(lead_dependency, raise_on_ignored: raise_on_ignored?(lead_dependency))
      log_checking_for_update(lead_dependency)

      return if all_versions_ignored?(lead_dependency, checker)

      return close_pull_request(reason: :up_to_date) if checker.up_to_date?

      requirements_to_unlock = requirements_to_unlock(checker)
      log_requirements_for_update(requirements_to_unlock, checker)

      return close_pull_request(reason: :update_no_longer_possible) if requirements_to_unlock == :update_not_possible

      updated_deps = checker.updated_dependencies(
        requirements_to_unlock: requirements_to_unlock
      )

      updated_files = generate_dependency_files_for(updated_deps)
      updated_deps = updated_deps.reject do |d|
        next false if d.name == checker.dependency.name
        next true if d.top_level? && d.requirements == d.previous_requirements

        d.version == d.previous_version
      end

      # NOTE: Gradle, Maven and Nuget dependency names can be case-insensitive
      # and the dependency name in the security advisory often doesn't match
      # what users have specified in their manifest.
      job_dependencies = job.dependencies.map(&:downcase)
      if updated_deps.map(&:name).map(&:downcase) != job_dependencies
        # The dependencies being updated have changed. Close the existing
        # multi-dependency PR and try creating a new one.
        close_pull_request(reason: :dependencies_changed)
        create_pull_request(updated_deps, updated_files, pr_message(updated_deps, updated_files))
      elsif existing_pull_request(updated_deps)
        # The existing PR is for this version. Update it.
        update_pull_request(updated_deps, updated_files)
      else
        # The existing PR is for a previous version. Supersede it.
        create_pull_request(updated_deps, updated_files, pr_message(updated_deps, updated_files))
      end
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity
    # rubocop:enable Metrics/MethodLength

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

    def raise_on_ignored?(dependency)
      job.security_updates_only? || ignore_conditions_for(dependency).any?
    end

    def record_security_update_not_needed_error(checker)
      logger_info(
        "no security update needed as #{checker.dependency.name} " \
        "is no longer vulnerable"
      )

      record_error(
        {
          "error-type": "security_update_not_needed",
          "error-detail": {
            "dependency-name": checker.dependency.name
          }
        }
      )
    end

    def record_security_update_ignored(checker)
      logger_info(
        "Dependabot cannot update to the required version as all versions " \
        "were ignored for #{checker.dependency.name}"
      )

      record_error(
        {
          "error-type": "all_versions_ignored",
          "error-detail": {
            "dependency-name": checker.dependency.name
          }
        }
      )
    end

    def record_dependency_file_not_supported_error(checker)
      logger_info(
        "Dependabot can't update vulnerable dependencies for projects " \
        "without a lockfile or pinned version requirement as the currently " \
        "installed version of #{checker.dependency.name} isn't known."
      )

      record_error(
        {
          "error-type": "dependency_file_not_supported",
          "error-detail": {
            "dependency-name": checker.dependency.name
          }
        }
      )
    end

    def record_security_update_not_possible_error(checker)
      latest_allowed_version =
        (checker.lowest_resolvable_security_fix_version ||
         checker.dependency.version)&.to_s
      lowest_non_vulnerable_version =
        checker.lowest_security_fix_version&.to_s
      conflicting_dependencies = checker.conflicting_dependencies

      logger_info(
        security_update_not_possible_message(checker, latest_allowed_version,
                                             conflicting_dependencies)
      )
      logger_info(earliest_fixed_version_message(lowest_non_vulnerable_version))

      record_error(
        {
          "error-type": "security_update_not_possible",
          "error-detail": {
            "dependency-name": checker.dependency.name,
            "latest-resolvable-version": latest_allowed_version,
            "lowest-non-vulnerable-version": lowest_non_vulnerable_version,
            "conflicting-dependencies": conflicting_dependencies
          }
        }
      )
    end

    def record_security_update_not_found(checker)
      logger_info(
        "Dependabot can't find a published or compatible non-vulnerable " \
        "version for #{checker.dependency.name}. " \
        "The latest available version is #{checker.dependency.version}"
      )

      record_error(
        {
          "error-type": "security_update_not_found",
          "error-detail": {
            "dependency-name": checker.dependency.name,
            "dependency-version": checker.dependency.version
          }
        }
      )
    end

    def record_pull_request_exists_for_latest_version(checker)
      record_error(
        {
          "error-type": "pull_request_exists_for_latest_version",
          "error-detail": {
            "dependency-name": checker.dependency.name,
            "dependency-version": checker.latest_version&.to_s
          }
        }
      )
    end

    def record_pull_request_exists_for_security_update(existing_pull_request)
      updated_dependencies = existing_pull_request.map do |dep|
        {
          "dependency-name": dep.fetch("dependency-name"),
          "dependency-version": dep.fetch("dependency-version", nil),
          "dependency-removed": dep.fetch("dependency-removed", nil)
        }.compact
      end
      record_error(
        {
          "error-type": "pull_request_exists_for_security_update",
          "error-detail": {
            "updated-dependencies": updated_dependencies
          }
        }
      )
    end

    def earliest_fixed_version_message(lowest_non_vulnerable_version)
      if lowest_non_vulnerable_version
        "The earliest fixed version is #{lowest_non_vulnerable_version}."
      else
        "Dependabot could not find a non-vulnerable version"
      end
    end

    def security_update_not_possible_message(checker, latest_allowed_version,
                                             conflicting_dependencies)
      if conflicting_dependencies.any?
        dep_messages = conflicting_dependencies.map do |dep|
          "  #{dep['explanation']}"
        end.join("\n")

        dependencies_pluralized =
          conflicting_dependencies.count > 1 ? "dependencies" : "dependency"

        "The latest possible version that can be installed is " \
          "#{latest_allowed_version} because of the following " \
          "conflicting #{dependencies_pluralized}:\n\n#{dep_messages}"
      else
        "The latest possible version of #{checker.dependency.name} that can " \
          "be installed is #{latest_allowed_version}"
      end
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

    # If a version update for a peer dependency is possible we should
    # defer to the PR that will be created for it to avoid duplicate PRs.
    def peer_dependency_should_update_instead?(dependency_name, updated_deps)
      # This doesn't apply to security updates as we can't rely on the
      # peer dependency getting updated.
      return false if job.security_updates_only?

      updated_deps.
        reject { |dep| dep.name == dependency_name }.
        any? do |dep|
          next true if existing_pull_request([dep])

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

    def log_checking_for_update(dependency)
      logger_info(
        "Checking if #{dependency.name} #{dependency.version} needs updating"
      )
      log_ignore_conditions(dependency)
    end

    def all_versions_ignored?(dependency, checker)
      logger_info("Latest version is #{checker.latest_version}")
      false
    rescue Dependabot::AllVersionsIgnored
      logger_info("All updates for #{dependency.name} were ignored")

      # Report this error to the backend to create an update job error
      raise if job.security_updates_only?

      true
    end

    def log_ignore_conditions(dep)
      conditions = job.ignore_conditions.
                   select { |ic| name_match?(ic["dependency-name"], dep.name) }
      return if conditions.empty?

      logger_info("Ignored versions:")
      conditions.each do |ic|
        logger_info("  #{ic['version-requirement']} - from #{ic['source']}") unless ic["version-requirement"].nil?

        ic["update-types"]&.each do |update_type|
          msg = "  #{update_type} - from #{ic['source']}"
          msg += " (doesn't apply to security update)" if job.security_updates_only?
          logger_info(msg)
        end
      end
    end

    def log_up_to_date(dependency)
      logger_info(
        "No update needed for #{dependency.name} #{dependency.version}"
      )
    end

    def log_error(dependency:, error:, error_type:, error_detail: nil)
      if error_type == "unknown_error"
        logger_error "Error processing #{dependency.name} (#{error.class.name})"
        logger_error error.message
        error.backtrace.each { |line| logger_error line }
      else
        logger_info(
          "Handled error whilst updating #{dependency.name}: #{error_type} " \
          "#{error_detail}"
        )
      end
    end

    def log_requirements_for_update(requirements_to_unlock, checker)
      logger_info("Requirements to unlock #{requirements_to_unlock}")

      return unless checker.respond_to?(:requirements_update_strategy)

      logger_info(
        "Requirements update strategy #{checker.requirements_update_strategy}"
      )
    end

    def pr_exists_for_latest_version?(checker)
      latest_version = checker.latest_version&.to_s
      return false if latest_version.nil?

      job.existing_pull_requests.
        select { |pr| pr.count == 1 }.
        map(&:first).
        select { |pr| pr.fetch("dependency-name") == checker.dependency.name }.
        any? { |pr| pr.fetch("dependency-version", nil) == latest_version }
    end

    def existing_pull_request(updated_dependencies)
      new_pr_set = Set.new(
        updated_dependencies.map do |dep|
          {
            "dependency-name" => dep.name,
            "dependency-version" => dep.version,
            "dependency-removed" => dep.removed? ? true : nil
          }.compact
        end
      )

      job.existing_pull_requests.find { |pr| Set.new(pr) == new_pr_set } ||
        created_pull_requests.find { |pr| Set.new(pr) == new_pr_set }
    end

    # rubocop:disable Metrics/PerceivedComplexity
    def dependencies
      all_deps = dependency_file_parser.parse

      # Tell the backend about the current dependencies on the target branch
      update_dependency_list(all_deps)

      # Rebases and security updates have dependencies, version updates don't
      if job.dependencies
        # Gradle, Maven and Nuget dependency names can be case-insensitive and
        # the dependency name in the security advisory often doesn't match what
        # users have specified in their manifest.
        #
        # It's technically possibly to publish case-sensitive npm packages to a
        # private registry but shouldn't cause problems here as job.dependencies
        # is set either from an existing PR rebase/recreate or a security
        # advisory.
        job_dependencies = job.dependencies.map(&:downcase)
        return all_deps.select do |dep|
          job_dependencies.include?(dep.name.downcase)
        end
      end

      allowed_deps = all_deps.select { |d| job.allowed_update?(d) }
      # Return dependencies in a random order, with top-level dependencies
      # considered first so that dependency runs which time out don't always hit
      # the same dependencies
      allowed_deps = allowed_deps.shuffle unless ENV["UPDATER_DETERMINISTIC"]

      if all_deps.any? && allowed_deps.none?
        logger_info("Found no dependencies to update after filtering allowed " \
                    "updates")
      end

      # Consider updating vulnerable deps first. Only consider the first 10,
      # though, to ensure they don't take up the entire update run
      deps = allowed_deps.select { |d| job.vulnerable?(d) }.sample(10) +
             allowed_deps.reject { |d| job.vulnerable?(d) }

      deps
    rescue StandardError => e
      handle_parser_error(e)
      []
    end
    # rubocop:enable Metrics/PerceivedComplexity

    def dependency_file_parser
      Dependabot::FileParsers.for_package_manager(job.package_manager).new(
        dependency_files: dependency_files,
        repo_contents_path: repo_contents_path,
        source: job.source,
        credentials: credentials,
        reject_external_code: job.reject_external_code?,
        options: job.experiments
      )
    end

    def update_checker_for(dependency, raise_on_ignored:)
      Dependabot::UpdateCheckers.for_package_manager(job.package_manager).new(
        dependency: dependency,
        dependency_files: dependency_files,
        repo_contents_path: repo_contents_path,
        credentials: credentials,
        ignored_versions: ignore_conditions_for(dependency),
        security_advisories: security_advisories_for(dependency),
        raise_on_ignored: raise_on_ignored,
        requirements_update_strategy: job.requirements_update_strategy,
        options: job.experiments
      )
    end

    def file_updater_for(dependencies)
      Dependabot::FileUpdaters.for_package_manager(job.package_manager).new(
        dependencies: dependencies,
        dependency_files: dependency_files,
        repo_contents_path: repo_contents_path,
        credentials: credentials,
        options: job.experiments
      )
    end

    def ignore_conditions_for(dep)
      update_config_ignored_versions(job.ignore_conditions, dep)
    end

    def update_config_ignored_versions(ignore_conditions, dep)
      ignore_conditions = ignore_conditions.map do |ic|
        Dependabot::Config::IgnoreCondition.new(
          dependency_name: ic["dependency-name"],
          versions: [ic["version-requirement"]].compact,
          update_types: ic["update-types"]
        )
      end
      Dependabot::Config::UpdateConfig.
        new(ignore_conditions: ignore_conditions).
        ignored_versions_for(dep, security_updates_only: job.security_updates_only?)
    end

    def name_match?(name1, name2)
      WildcardMatcher.match?(
        job.name_normaliser.call(name1),
        job.name_normaliser.call(name2)
      )
    end

    def security_advisories_for(dep)
      relevant_advisories =
        job.security_advisories.
        select { |adv| adv.fetch("dependency-name").casecmp(dep.name).zero? }

      relevant_advisories.map do |adv|
        vulnerable_versions = adv["affected-versions"] || []
        safe_versions = (adv["patched-versions"] || []) +
                        (adv["unaffected-versions"] || [])

        Dependabot::SecurityAdvisory.new(
          dependency_name: dep.name,
          package_manager: job.package_manager,
          vulnerable_versions: vulnerable_versions,
          safe_versions: safe_versions
        )
      end
    end

    def generate_dependency_files_for(updated_dependencies)
      if updated_dependencies.count == 1
        updated_dependency = updated_dependencies.first
        logger_info("Updating #{updated_dependency.name} from " \
                    "#{updated_dependency.previous_version} to " \
                    "#{updated_dependency.version}")
      else
        dependency_names = updated_dependencies.map(&:name)
        logger_info("Updating #{dependency_names.join(', ')}")
      end

      # Ignore dependencies that are tagged as information_only. These will be
      # updated indirectly as a result of a parent dependency update and are
      # only included here to be included in the PR info.
      deps_to_update = updated_dependencies.reject(&:informational_only?)
      updater = file_updater_for(deps_to_update)
      updater.updated_dependency_files
    end

    def create_pull_request(dependencies, updated_dependency_files, pr_message)
      logger_info("Submitting #{dependencies.map(&:name).join(', ')} " \
                  "pull request for creation")

      service.create_pull_request(
        job_id,
        dependencies,
        updated_dependency_files.map(&:to_h),
        base_commit_sha,
        pr_message
      )

      created_pull_requests << dependencies.map do |dep|
        {
          "dependency-name" => dep.name,
          "dependency-version" => dep.version,
          "dependency-removed" => dep.removed? ? true : nil
        }.compact
      end
    end

    def update_pull_request(dependencies, updated_dependency_files)
      logger_info("Submitting #{dependencies.map(&:name).join(', ')} " \
                  "pull request for update")

      service.update_pull_request(
        job_id,
        dependencies,
        updated_dependency_files.map(&:to_h),
        base_commit_sha
      )
    end

    def close_pull_request(reason:)
      reason_string = reason.to_s.tr("_", " ")
      logger_info("Telling backend to close pull request for " \
                  "#{job.dependencies.join(', ')} - #{reason_string}")
      service.close_pull_request(job_id, job.dependencies, reason)
    end

    # rubocop:disable Metrics/MethodLength
    def handle_dependabot_error(error:, dependency:)
      error_details =
        case error
        when Dependabot::DependencyFileNotResolvable
          {
            "error-type": "dependency_file_not_resolvable",
            "error-detail": { message: error.message }
          }
        when Dependabot::DependencyFileNotEvaluatable
          {
            "error-type": "dependency_file_not_evaluatable",
            "error-detail": { message: error.message }
          }
        when Dependabot::GitDependenciesNotReachable
          {
            "error-type": "git_dependencies_not_reachable",
            "error-detail": { "dependency-urls": error.dependency_urls }
          }
        when Dependabot::GitDependencyReferenceNotFound
          {
            "error-type": "git_dependency_reference_not_found",
            "error-detail": { dependency: error.dependency }
          }
        when Dependabot::PrivateSourceAuthenticationFailure
          {
            "error-type": "private_source_authentication_failure",
            "error-detail": { source: error.source }
          }
        when Dependabot::PrivateSourceTimedOut
          {
            "error-type": "private_source_timed_out",
            "error-detail": { source: error.source }
          }
        when Dependabot::PrivateSourceCertificateFailure
          {
            "error-type": "private_source_certificate_failure",
            "error-detail": { source: error.source }
          }
        when Dependabot::MissingEnvironmentVariable
          {
            "error-type": "missing_environment_variable",
            "error-detail": {
              "environment-variable": error.environment_variable
            }
          }
        when Dependabot::GoModulePathMismatch
          {
            "error-type": "go_module_path_mismatch",
            "error-detail": {
              "declared-path": error.declared_path,
              "discovered-path": error.discovered_path,
              "go-mod": error.go_mod
            }
          }
        when Dependabot::NotImplemented
          {
            "error-type": "not_implemented",
            "error-detail": {
              message: error.message
            }
          }
        when Dependabot::SharedHelpers::HelperSubprocessFailed
          # If a helper subprocess has failed the error may include sensitive
          # info such as file contents or paths. This information is already
          # in the job logs, so we send a breadcrumb to Sentry to retrieve those
          # instead.
          msg = "Subprocess #{error.raven_context[:fingerprint]} failed to run. Check the job logs for error messages"
          sanitized_error = SubprocessFailed.new(msg, raven_context: error.raven_context)
          sanitized_error.set_backtrace(error.backtrace)
          Raven.capture_exception(sanitized_error, raven_context)

          { "error-type": "unknown_error" }
        when *Octokit::RATE_LIMITED_ERRORS
          # If we get a rate-limited error we let dependabot-api handle the
          # retry by re-enqueing the update job after the reset
          {
            "error-type": "octokit_rate_limited",
            "error-detail": {
              "rate-limit-reset": error.response_headers["X-RateLimit-Reset"]
            }
          }
        else
          Raven.capture_exception(error, raven_context(dependency: dependency))
          { "error-type": "unknown_error" }
        end

      record_error(error_details)

      log_error(
        dependency: dependency,
        error: error,
        error_type: error_details.fetch(:"error-type"),
        error_detail: error_details.fetch(:"error-detail", nil)
      )
    end

    # rubocop:enable Metrics/MethodLength
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity
    def handle_parser_error(error)
      error_details =
        case error
        when Dependabot::DependencyFileNotEvaluatable
          {
            "error-type": "dependency_file_not_evaluatable",
            "error-detail": { message: error.message }
          }
        when Dependabot::DependencyFileNotResolvable
          {
            "error-type": "dependency_file_not_resolvable",
            "error-detail": { message: error.message }
          }
        when Dependabot::BranchNotFound
          {
            "error-type": "branch_not_found",
            "error-detail": { "branch-name": error.branch_name }
          }
        when Dependabot::RepoNotFound
          # This happens if the repo gets removed after a job gets kicked off.
          # The main backend will handle it without any prompt from the updater,
          # so no need to add an error to the errors array
          nil
        when Dependabot::DependencyFileNotParseable
          {
            "error-type": "dependency_file_not_parseable",
            "error-detail": {
              message: error.message,
              "file-path": error.file_path
            }
          }
        when Dependabot::DependencyFileNotFound
          {
            "error-type": "dependency_file_not_found",
            "error-detail": { "file-path": error.file_path }
          }
        when Dependabot::PathDependenciesNotReachable
          {
            "error-type": "path_dependencies_not_reachable",
            "error-detail": { dependencies: error.dependencies }
          }
        when Dependabot::PrivateSourceAuthenticationFailure
          {
            "error-type": "private_source_authentication_failure",
            "error-detail": { source: error.source }
          }
        when Dependabot::GitDependenciesNotReachable
          {
            "error-type": "git_dependencies_not_reachable",
            "error-detail": { "dependency-urls": error.dependency_urls }
          }
        when Dependabot::NotImplemented
          {
            "error-type": "not_implemented",
            "error-detail": {
              message: error.message
            }
          }
        when Octokit::ServerError
          # If we get a 500 from GitHub there's very little we can do about it,
          # and responsibility for fixing it is on them, not us. As a result we
          # quietly log these as errors
          { "error-type": "unknown_error" }
        else
          raise if RUN_HALTING_ERRORS.keys.any? { |e| error.is_a?(e) }

          logger_error error.message
          error.backtrace.each { |line| logger_error line }

          Raven.capture_exception(error, raven_context)
          { "error-type": "unknown_error" }
        end

      record_error(error_details) if error_details
    end

    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity
    def pr_message(dependencies, files)
      Dependabot::PullRequestCreator::MessageBuilder.new(
        source: job.source,
        dependencies: dependencies,
        files: files,
        credentials: credentials,
        commit_message_options: job.commit_message_options,
        # This ensures that PR messages we build replace github.com links with
        # a redirect that stop markdown enriching them into mentions on the source
        # repository.
        #
        # TODO: Promote this value to a constant or similar once we have
        # updated core to avoid surprise outcomes if this is unset.
        github_redirection_service: "github-redirect.dependabot.com"
      ).message
    end

    def update_dependency_list(dependencies)
      service.update_dependency_list(
        job_id,
        dependencies.map do |dep|
          {
            name: dep.name,
            version: dep.version,
            requirements: dep.requirements
          }
        end,
        dependency_files.reject(&:support_file).map(&:path)
      )
    end

    def error_context(dependency)
      { dependency_name: dependency.name, update_job_id: job_id }
    end

    def credentials
      job.credentials
    end

    def logger_info(message)
      Dependabot.logger.info(prefixed_log_message(message))
    end

    def logger_error(message)
      Dependabot.logger.error(prefixed_log_message(message))
    end

    def prefixed_log_message(message)
      message.lines.map { |line| [log_prefix, line].join(" ") }.join
    end

    def log_prefix
      "<job_#{job_id}>" if job_id
    end

    def record_error(error_details)
      service.record_update_job_error(
        job_id,
        error_type: error_details.fetch(:"error-type"),
        error_details: error_details[:"error-detail"]
      )

      errors << error_details
    end

    def raven_context(dependency: nil)
      context = { tags: {}, extra: { update_job_id: job_id } }
      context[:tags][:package_manager] = @job.package_manager if @job
      context[:extra][:dependency_name] = dependency.name if dependency
      context
    end
  end
end
# rubocop:enable Metrics/ClassLength
