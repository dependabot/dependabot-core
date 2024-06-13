# typed: true
# frozen_string_literal: true

require "dependabot/updater/security_update_helpers"

# This class implements our strategy for updating a single, insecure dependency
# to a secure version. We attempt to make the smallest version update possible,
# i.e. semver patch-level increase is preferred over minor-level increase.
module Dependabot
  class Updater
    module Operations
      class CreateSecurityUpdatePullRequest
        include SecurityUpdateHelpers

        class SecurityUpdateError < StandardError
          def initialize(message:, error_context:)
            super(message)
            @error_context = error_context
          end

          def sentry_context
            { extra: @error_context }
          end
        end

        def self.applies_to?(job:)
          return false if job.updating_a_pull_request?
          # If we haven't been given data for the vulnerable dependency,
          # this strategy cannot act.
          return false unless job.dependencies&.any?

          job.security_updates_only?
        end

        def self.tag_name
          :create_security_pr
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          # TODO: Collect @created_pull_requests on the Job object?
          @created_pull_requests = []
        end

        # TODO: We currently tolerate multiple dependencies for this operation
        #       but in reality, we only expect a single dependency per job.
        #
        # Changing this contract now without some safety catches introduces
        # risk, so we'll maintain the interface as-is for now, but this is
        # something we should make much more intentional in future.
        def perform
          Dependabot.logger.info("Starting security update job for #{job.source.repo}")

          target_dependencies = dependency_snapshot.job_dependencies

          if target_dependencies.empty?
            record_security_update_dependency_not_found
          else
            target_dependencies.each { |dep| check_and_create_pr_with_error_handling(dep) }
          end
        end

        private

        attr_reader :job
        attr_reader :service
        attr_reader :dependency_snapshot
        attr_reader :error_handler
        attr_reader :created_pull_requests

        def check_and_create_pr_with_error_handling(dependency)
          check_and_create_pull_request(dependency)
        rescue Dependabot::InconsistentRegistryResponse => e
          error_handler.log_dependency_error(
            dependency: dependency,
            error: e,
            error_type: "inconsistent_registry_response",
            error_detail: e.message
          )
        rescue StandardError => standard_ex
          security_ex = SecurityUpdateError.new(message: "Security Update Error, #{standard_ex.message}",
          error_context: standard_ex.instance_variable_get(:@error_context))
          security_ex.set_backtrace(standard_ex.backtrace)
          error_handler.handle_dependency_error(error: security_ex, dependency: dependency)
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        def check_and_create_pull_request(dependency)
          dependency = vulnerable_version(dependency) if dependency.metadata[:all_versions]
          checker = update_checker_for(dependency)

          log_checking_for_update(dependency)

          Dependabot.logger.info("Latest version is #{checker.latest_version}")

          unless checker.vulnerable?
            # The current dependency isn't vulnerable if the version is correct and
            # can be matched against the advisories affected versions
            if checker.version_class.correct?(checker.dependency.version)
              return record_security_update_not_needed_error(checker.dependency)
            end

            return record_dependency_file_not_supported_error(checker)
          end

          return record_security_update_ignored(checker) unless job.allowed_update?(dependency)

          # The current version is still vulnerable and  Dependabot can't find a
          # published or compatible non-vulnerable version, this can happen if the
          # fixed version hasn't been published yet or the published version isn't
          # compatible with the current environment (e.g. python version) or
          # version (uses a different version suffix for gradle/maven)
          return record_security_update_not_found(checker) if checker.up_to_date?

          if pr_exists_for_latest_version?(checker)
            Dependabot.logger.info(
              "Pull request already exists for #{checker.dependency.name} " \
              "with latest version #{checker.latest_version}"
            )
            return record_pull_request_exists_for_latest_version(checker)
          end

          requirements_to_unlock = requirements_to_unlock(checker)
          log_requirements_for_update(requirements_to_unlock, checker)
          return record_security_update_not_possible_error(checker) if requirements_to_unlock == :update_not_possible

          updated_deps = checker.updated_dependencies(
            requirements_to_unlock: requirements_to_unlock
          )

          # Prevent updates that don't end up fixing any security advisories,
          # blocking any updates where dependabot-core updates to a vulnerable
          # version. This happens for npm/yarn sub-dependencies where Dependabot has no
          # control over the target version. Related issue:
          #   https://github.com/github/dependabot-api/issues/905
          return record_security_update_not_possible_error(checker) if updated_deps.none? { |d| job.security_fix?(d) }

          if (existing_pr = existing_pull_request(updated_deps))
            # Create a update job error to prevent dependabot-api from creating a
            # update_not_possible error, this is likely caused by a update job retry
            # so should be invisible to users (as the first job completed with a pull
            # request)
            record_pull_request_exists_for_security_update(existing_pr)

            deps = existing_pr.map do |dep|
              if dep.fetch("dependency-removed", false)
                "#{dep.fetch('dependency-name')}@removed"
              else
                "#{dep.fetch('dependency-name')}@#{dep.fetch('dependency-version')}"
              end
            end

            return Dependabot.logger.info(
              "Pull request already exists for #{deps.join(', ')}"
            )
          end

          dependency_change = Dependabot::DependencyChangeBuilder.create_from(
            job: job,
            dependency_files: dependency_snapshot.dependency_files,
            updated_dependencies: updated_deps,
            change_source: checker.dependency
          )

          create_pull_request(dependency_change)
        rescue Dependabot::AllVersionsIgnored
          Dependabot.logger.info("All updates for #{dependency.name} were ignored")
          # Report this error to the backend to create an update job error
          raise
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        def vulnerable_version(dependency)
          return dependency if dependency.metadata[:all_versions].count == 1

          vulnerable_dependency = dependency.metadata[:all_versions].find do |dep|
            checker = update_checker_for(dep)
            checker.version_class.correct?(dep.version) && checker.vulnerable?
          end

          # this will lead to a security update not found error
          return dependency unless vulnerable_dependency

          vulnerable_dependency
        end

        def update_checker_for(dependency)
          Dependabot::UpdateCheckers.for_package_manager(job.package_manager).new(
            dependency: dependency,
            dependency_files: dependency_snapshot.dependency_files,
            repo_contents_path: job.repo_contents_path,
            credentials: job.credentials,
            ignored_versions: job.ignore_conditions_for(dependency),
            security_advisories: job.security_advisories_for(dependency),
            raise_on_ignored: true, # always true for security updates
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

        def log_up_to_date(dependency)
          Dependabot.logger.info(
            "No update needed for #{dependency.name} #{dependency.version}"
          )
        end

        def log_requirements_for_update(requirements_to_unlock, checker)
          Dependabot.logger.info("Requirements to unlock #{requirements_to_unlock}")

          return unless checker.respond_to?(:requirements_update_strategy)

          Dependabot.logger.info(
            "Requirements update strategy #{checker.requirements_update_strategy&.serialize}"
          )
        end

        def pr_exists_for_latest_version?(checker)
          latest_version = checker.latest_version&.to_s
          return false if latest_version.nil?

          job.existing_pull_requests
             .select { |pr| pr.count == 1 }
             .map(&:first)
             .select { |pr| pr.fetch("dependency-name") == checker.dependency.name }
             .any? { |pr| pr.fetch("dependency-version", nil) == latest_version }
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

        def create_pull_request(dependency_change)
          Dependabot.logger.info("Submitting #{dependency_change.updated_dependencies.map(&:name).join(', ')} " \
                                 "pull request for creation")

          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)

          created_pull_requests << dependency_change.updated_dependencies.map do |dep|
            {
              "dependency-name" => dep.name,
              "dependency-version" => dep.version,
              "dependency-removed" => dep.removed? ? true : nil
            }.compact
          end
        end
      end
    end
  end
end
