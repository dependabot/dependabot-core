# typed: strict
# frozen_string_literal: true

require "dependabot/updater/security_update_helpers"
require "dependabot/notices"

# This class implements our strategy for updating a single, insecure dependency
# to a secure version. We attempt to make the smallest version update possible,
# i.e. semver patch-level increase is preferred over minor-level increase.
module Dependabot
  class Updater
    module Operations
      class CreateSecurityUpdatePullRequest
        extend T::Sig
        include SecurityUpdateHelpers
        include PullRequestHelpers

        sig { params(job: Job).returns(T::Boolean) }
        def self.applies_to?(job:)
          return false if job.updating_a_pull_request?
          # If we haven't been given data for the vulnerable dependency,
          # this strategy cannot act.
          return false unless job.dependencies&.any?

          job.security_updates_only?
        end

        sig { returns(Symbol) }
        def self.tag_name
          :create_security_pr
        end

        sig do
          params(
            service: Dependabot::Service,
            job: Dependabot::Job,
            dependency_snapshot: Dependabot::DependencySnapshot,
            error_handler: Dependabot::Updater::ErrorHandler
          ).void
        end
        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          # TODO: Collect @created_pull_requests on the Job object?
          @created_pull_requests = T.let([], T::Array[PullRequest])
          # A list of notices that will be used in PR messages and/or sent to the dependabot github alerts.
          @notices = T.let([], T::Array[Dependabot::Notice])
        end

        # TODO: We currently tolerate multiple dependencies for this operation
        #       but in reality, we only expect a single dependency per job.
        #
        # Changing this contract now without some safety catches introduces
        # risk, so we'll maintain the interface as-is for now, but this is
        # something we should make much more intentional in future.
        sig { void }
        def perform
          Dependabot.logger.info("Starting security update job for #{job.source.repo}")

          # Retrieve the list of initial notices from dependency snapshot
          @notices = dependency_snapshot.notices
          # More notices can be added during the update process

          target_dependencies = dependency_snapshot.job_dependencies

          if target_dependencies.empty?
            record_security_update_dependency_not_found
          else
            target_dependencies.each { |dep| check_and_create_pr_with_error_handling(dep) }
          end
        end

        private

        sig { returns(Dependabot::Job) }
        attr_reader :job
        sig { returns(Dependabot::Service) }
        attr_reader :service
        sig { returns(Dependabot::DependencySnapshot) }
        attr_reader :dependency_snapshot
        sig { returns(Dependabot::Updater::ErrorHandler) }
        attr_reader :error_handler
        sig { returns(T::Array[PullRequest]) }
        attr_reader :created_pull_requests
        # A list of notices that will be used in PR messages and/or sent to the dependabot github alerts.
        sig { returns(T::Array[Dependabot::Notice]) }
        attr_reader :notices

        sig { params(dependency: Dependabot::Dependency).void }
        def check_and_create_pr_with_error_handling(dependency)
          check_and_create_pull_request(dependency)
        rescue Dependabot::InconsistentRegistryResponse => e
          error_handler.log_dependency_error(
            dependency: dependency,
            error: e,
            error_type: "inconsistent_registry_response",
            error_detail: e.message
          )
        rescue StandardError => e
          error_handler.handle_dependency_error(error: e, dependency: dependency)
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        sig { params(dependency: Dependabot::Dependency).void }
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

            deps = existing_pr.dependencies.map do |dep|
              if dep.removed?
                "#{dep.name}@removed"
              else
                "#{dep.name}@#{dep.version}"
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
            change_source: checker.dependency,
            # Sending notices to the pr message builder to be used in the PR message if show_in_pr is true
            notices: @notices
          )

          # Send warning alerts to the API if any warning notices are present.
          # Note that only notices with notice.show_alert set to true will be sent.
          record_warning_notices(notices) if notices.any?

          create_pull_request(dependency_change)
        rescue Dependabot::AllVersionsIgnored
          Dependabot.logger.info("All updates for #{dependency.name} were ignored")
          # Report this error to the backend to create an update job error
          raise
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity
        sig { params(dependency: Dependabot::Dependency).returns(Dependabot::Dependency) }
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

        sig { params(dependency: Dependabot::Dependency).returns(Dependabot::UpdateCheckers::Base) }
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

        sig { params(dependency: Dependabot::Dependency).void }
        def log_checking_for_update(dependency)
          Dependabot.logger.info(
            "Checking if #{dependency.name} #{dependency.version} needs updating"
          )
          job.log_ignore_conditions_for(dependency)
        end

        sig { params(dependency: Dependabot::Dependency).void }
        def log_up_to_date(dependency)
          Dependabot.logger.info(
            "No update needed for #{dependency.name} #{dependency.version}"
          )
        end

        sig { params(requirements_to_unlock: Symbol, checker: Dependabot::UpdateCheckers::Base).void }
        def log_requirements_for_update(requirements_to_unlock, checker)
          Dependabot.logger.info("Requirements to unlock #{requirements_to_unlock}")

          return unless checker.respond_to?(:requirements_update_strategy)

          Dependabot.logger.info(
            "Requirements update strategy #{checker.requirements_update_strategy&.serialize}"
          )
        end

        sig { params(checker: Dependabot::UpdateCheckers::Base).returns(T::Boolean) }
        def pr_exists_for_latest_version?(checker)
          latest_version = checker.latest_version&.to_s
          return false if latest_version.nil?

          job.existing_pull_requests
             .any? { |pr| pr.contains_dependency?(checker.dependency.name, latest_version) } ||
            created_pull_requests.any? { |pr| pr.contains_dependency?(checker.dependency.name, latest_version) }
        end

        sig do
          params(updated_dependencies: T::Array[Dependabot::Dependency])
            .returns(T.nilable(PullRequest))
        end
        def existing_pull_request(updated_dependencies)
          new_pr = PullRequest.create_from_updated_dependencies(updated_dependencies)

          job.existing_pull_requests.find { |pr| pr == new_pr } ||
            created_pull_requests.find { |pr| pr == new_pr }
        end

        sig { params(checker: Dependabot::UpdateCheckers::Base).returns(Symbol) }
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

        sig { params(dependency_change: Dependabot::DependencyChange).void }
        def create_pull_request(dependency_change)
          Dependabot.logger.info("Submitting #{dependency_change.updated_dependencies.map(&:name).join(', ')} " \
                                 "pull request for creation")

          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)

          created_pull_requests << PullRequest.create_from_updated_dependencies(dependency_change.updated_dependencies)
        end
      end
    end
  end
end
