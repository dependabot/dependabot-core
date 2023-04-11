# frozen_string_literal: true

# This class implements our strategy for updating a single, insecure dependency
# to a secure version. We attempt to make the smallest version update possible,
# i.e. semver patch-level increase is preferred over minor-level increase.
module Dependabot
  class Updater
    module Operations
      class CreateSecurityUpdatePullRequest
        def self.applies_to?(job:)
          return false if job.updating_a_pull_request?
          # If we haven't been given data for the vulnerable dependency,
          # this strategy cannot act.
          return false if job.dependencies&.none?

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
          Dependabot.logger.info("Starting update job for #{job.source.repo}")
          dependency_snapshot.job_dependencies.each { |dep| check_and_create_pr_with_error_handling(dep) }
        end

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler,
                    :created_pull_requests

        def check_and_create_pr_with_error_handling(dependency)
          check_and_create_pull_request(dependency)
        rescue Dependabot::InconsistentRegistryResponse => e
          error_handler.log_error(
            dependency: dependency,
            error: e,
            error_type: "inconsistent_registry_response",
            error_detail: e.message
          )
        rescue StandardError => e
          error_handler.handle_dependabot_error(error: e, dependency: dependency)
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
            return Dependabot.logger.info(
              "Pull request already exists for #{checker.dependency.name} " \
              "with latest version #{checker.latest_version}"
            )
          end

          requirements_to_unlock = requirements_to_unlock(checker)
          log_requirements_for_update(requirements_to_unlock, checker)

          if requirements_to_unlock == :update_not_possible
            return record_security_update_not_possible_error(checker) if job.security_updates_only? && job.dependencies

            return Dependabot.logger.info(
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

            return Dependabot.logger.info(
              "Pull request already exists for #{deps.join(', ')}"
            )
          end

          if peer_dependency_should_update_instead?(checker.dependency.name, updated_deps)
            return Dependabot.logger.info(
              "No update possible for #{dependency.name} #{dependency.version} " \
              "(peer dependency can be updated)"
            )
          end

          dependency_change = Dependabot::DependencyChangeBuilder.create_from(
            job: job,
            dependency_files: dependency_snapshot.dependency_files,
            updated_dependencies: updated_deps,
            change_source: checker.dependency
          )
          create_pull_request(dependency_change)
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def raise_on_ignored?(dependency)
          job.security_updates_only? || job.ignore_conditions_for(dependency).any?
        end

        def update_checker_for(dependency, raise_on_ignored:)
          Dependabot::UpdateCheckers.for_package_manager(job.package_manager).new(
            dependency: dependency,
            dependency_files: dependency_snapshot.dependency_files,
            repo_contents_path: job.repo_contents_path,
            credentials: job.credentials,
            ignored_versions: job.ignore_conditions_for(dependency),
            security_advisories: job.security_advisories_for(dependency),
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

          # Report this error to the backend to create an update job error
          raise if job.security_updates_only?

          true
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

        ### BEGIN: Security Update Helpers
        def raise_on_ignored?(dependency)
          job.security_updates_only? || job.ignore_conditions_for(dependency).any?
        end

        def record_security_update_not_needed_error(checker)
          Dependabot.logger.info(
            "no security update needed as #{checker.dependency.name} " \
            "is no longer vulnerable"
          )

          service.record_update_job_error(
            error_type: "security_update_not_needed",
            error_details: {
              "dependency-name": checker.dependency.name
            }
          )
        end

        def record_security_update_ignored(checker)
          Dependabot.logger.info(
            "Dependabot cannot update to the required version as all versions " \
            "were ignored for #{checker.dependency.name}"
          )

          service.record_update_job_error(
            error_type: "all_versions_ignored",
            error_details: {
              "dependency-name": checker.dependency.name
            }
          )
        end

        def record_dependency_file_not_supported_error(checker)
          Dependabot.logger.info(
            "Dependabot can't update vulnerable dependencies for projects " \
            "without a lockfile or pinned version requirement as the currently " \
            "installed version of #{checker.dependency.name} isn't known."
          )

          service.record_update_job_error(
            error_type: "dependency_file_not_supported",
            error_details: {
              "dependency-name": checker.dependency.name
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

          Dependabot.logger.info(
            security_update_not_possible_message(checker, latest_allowed_version,
                                                 conflicting_dependencies)
          )
          Dependabot.logger.info(earliest_fixed_version_message(lowest_non_vulnerable_version))

          service.record_update_job_error(
            error_type: "security_update_not_possible",
            error_details: {
              "dependency-name": checker.dependency.name,
              "latest-resolvable-version": latest_allowed_version,
              "lowest-non-vulnerable-version": lowest_non_vulnerable_version,
              "conflicting-dependencies": conflicting_dependencies
            }
          )
        end

        def record_security_update_not_found(checker)
          Dependabot.logger.info(
            "Dependabot can't find a published or compatible non-vulnerable " \
            "version for #{checker.dependency.name}. " \
            "The latest available version is #{checker.dependency.version}"
          )

          service.record_update_job_error(
            error_type: "security_update_not_found",
            error_details: {
              "dependency-name": checker.dependency.name,
              "dependency-version": checker.dependency.version
            },
            dependency: checker.dependency
          )
        end

        def record_pull_request_exists_for_latest_version(checker)
          service.record_update_job_error(
            error_type: "pull_request_exists_for_latest_version",
            error_details: {
              "dependency-name": checker.dependency.name,
              "dependency-version": checker.latest_version&.to_s
            },
            dependency: checker.dependency
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

          service.record_update_job_error(
            error_type: "pull_request_exists_for_security_update",
            error_details: {
              "updated-dependencies": updated_dependencies
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
        ### END: Security Update Helpers

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

        def update_pull_request(dependency_change)
          Dependabot.logger.info("Submitting #{dependency_change.updated_dependencies.map(&:name).join(', ')} " \
                                 "pull request for update")

          service.update_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
        end

        def close_pull_request(reason:)
          reason_string = reason.to_s.tr("_", " ")
          Dependabot.logger.info("Telling backend to close pull request for " \
                                 "#{job.dependencies.join(', ')} - #{reason_string}")
          service.close_pull_request(job.dependencies, reason)
        end
      end
    end
  end
end
