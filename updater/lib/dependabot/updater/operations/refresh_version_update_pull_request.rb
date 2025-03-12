# typed: strong
# frozen_string_literal: true

require "dependabot/updater/security_update_helpers"
require "dependabot/notices"

# This class implements our strategy for 'refreshing' an existing Pull Request
# that updates a dependnency to the latest permitted version.
#
# It will determine if the existing diff is still relevant, in which case it
# functions similar to a "rebase", but in the case where the project folder's
# dependencies have changed or a newer version is available, it will supersede
# the existing pull request with a new one for clarity.
module Dependabot
  class Updater
    module Operations
      class RefreshVersionUpdatePullRequest
        extend T::Sig
        include PullRequestHelpers

        sig { params(job: Dependabot::Job).returns(T::Boolean) }
        def self.applies_to?(job:)
          return false if job.security_updates_only?
          # If we haven't been given metadata about the dependencies present
          # in the pull request, this strategy cannot act.
          return false if job.dependencies&.none?

          job.updating_a_pull_request?
        end

        sig { returns(Symbol) }
        def self.tag_name
          :update_version_pr
        end

        sig do
          params(
            service: Dependabot::Service,
            job: Dependabot::Job,
            dependency_snapshot: Dependabot::DependencySnapshot,
            error_handler: ErrorHandler
          ).void
        end
        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          # A list of notices that will be used in PR messages and/or sent to the dependabot github alerts.
          @notices = T.let([], T::Array[Dependabot::Notice])

          return unless job.source.directory.nil? && job.source.directories&.count == 1

          job.source.directory = job.source.directories&.first
        end

        sig { void }
        def perform
          Dependabot.logger.info("Starting update job for #{job.source.repo}")
          Dependabot.logger.info("Checking and updating versions pull requests...")
          dependency = dependencies.last

          # Retrieve the list of initial notices from dependency snapshot
          @notices = dependency_snapshot.notices
          # More notices can be added during the update process

          check_and_update_pull_request(dependencies)
        rescue StandardError => e
          error_handler.handle_dependency_error(error: e, dependency: dependency)
        ensure
          service.record_ecosystem_meta(dependency_snapshot.ecosystem)
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
        # A list of notices that will be used in PR messages and/or sent to the dependabot github alerts.
        sig { returns(T::Array[Dependabot::Notice]) }
        attr_reader :notices

        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies
          dependency_snapshot.job_dependencies
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        sig do
          params(dependencies: T::Array[Dependabot::Dependency]).void
        end
        def check_and_update_pull_request(dependencies)
          job_dependencies = T.must(job.dependencies)

          if job_dependencies.count.zero? || dependencies.count != job_dependencies.count
            # If the job dependencies mismatch the parsed dependencies, then
            # we should close the PR as at least one thing we changed has been
            # removed from the project.
            close_pull_request(reason: :dependency_removed)
            return
          end

          # The first dependency is the "lead" dependency in a multi-dependency
          # update - i.e., the one we're trying to update.
          #
          # Note: Gradle, Maven and Nuget dependency names can be case-insensitive
          # and the dependency name in the security advisory often doesn't match
          # what users have specified in their manifest.
          lead_dep_name = T.must(job_dependencies.first).downcase
          lead_dependency = dependencies.find do |dep|
            dep.name.downcase == lead_dep_name
          end

          if lead_dependency.nil?
            # If the lead dependency is not found, it indicates that one of the dependencies
            # we attempted to update has been removed from the project. Therefore, we should
            # close the PR.
            close_pull_request(reason: :dependency_removed)
            return
          end

          checker = update_checker_for(lead_dependency, raise_on_ignored: raise_on_ignored?(lead_dependency))
          log_checking_for_update(lead_dependency)

          return if all_versions_ignored?(lead_dependency, checker)

          return close_pull_request(reason: :up_to_date) if checker.up_to_date?

          requirements_to_unlock = requirements_to_unlock(checker)
          log_requirements_for_update(requirements_to_unlock, checker)

          if requirements_to_unlock == :update_not_possible
            return close_pull_request(reason: :update_no_longer_possible)
          end

          updated_deps = checker.updated_dependencies(
            requirements_to_unlock: requirements_to_unlock
          )

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

          # NOTE: Gradle, Maven and Nuget dependency names can be case-insensitive
          # and the dependency name in the security advisory often doesn't match
          # what users have specified in their manifest.
          job_dependencies = job_dependencies.map(&:downcase)
          if dependency_change.updated_dependencies.map { |x| x.name.downcase } != job_dependencies
            # The dependencies being updated have changed. Close the existing
            # multi-dependency PR and try creating a new one.
            close_pull_request(reason: :dependencies_changed)
            create_pull_request(dependency_change)
          elsif existing_pull_request(dependency_change.updated_dependencies)
            # The existing PR is for this version. Update it.
            update_pull_request(dependency_change)
          else
            # The existing PR is for a previous version. Supersede it.
            create_pull_request(dependency_change)
          end
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength

        sig { params(dependency_change: Dependabot::DependencyChange).void }
        def create_pull_request(dependency_change)
          Dependabot.logger.info("Submitting #{dependency_change.updated_dependencies.map(&:name).join(', ')} " \
                                 "pull request for creation")

          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
        end

        sig { params(dependency_change: Dependabot::DependencyChange).void }
        def update_pull_request(dependency_change)
          Dependabot.logger.info("Submitting #{dependency_change.updated_dependencies.map(&:name).join(', ')} " \
                                 "pull request for update")

          service.update_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
        end

        sig { params(reason: Symbol).void }
        def close_pull_request(reason:)
          job_dependencies = T.must(job.dependencies)

          reason_string = reason.to_s.tr("_", " ")
          Dependabot.logger.info("Telling backend to close pull request for " \
                                 "#{job_dependencies.join(', ')} - #{reason_string}")
          service.close_pull_request(job_dependencies, reason)
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def raise_on_ignored?(dependency)
          job.ignore_conditions_for(dependency).any?
        end

        sig do
          params(dependency: Dependabot::Dependency, raise_on_ignored: T::Boolean)
            .returns(Dependabot::UpdateCheckers::Base)
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
            update_cooldown: job.cooldown,
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

        sig do
          params(dependency: Dependabot::Dependency, checker: Dependabot::UpdateCheckers::Base).returns(T::Boolean)
        end
        def all_versions_ignored?(dependency, checker)
          Dependabot.logger.info("Latest version is #{checker.latest_version}")
          false
        rescue Dependabot::AllVersionsIgnored
          Dependabot.logger.info("All updates for #{dependency.name} were ignored")
          true
        end

        sig do
          params(checker: Dependabot::UpdateCheckers::Base).returns(Symbol)
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

        sig do
          params(requirements_to_unlock: Symbol, checker: Dependabot::UpdateCheckers::Base).void
        end
        def log_requirements_for_update(requirements_to_unlock, checker)
          Dependabot.logger.info("Requirements to unlock #{requirements_to_unlock}")

          return unless checker.respond_to?(:requirements_update_strategy)

          Dependabot.logger.info(
            "Requirements update strategy #{checker.requirements_update_strategy&.serialize}"
          )
        end

        sig do
          params(updated_dependencies: T::Array[Dependabot::Dependency])
            .returns(T.nilable(Dependabot::PullRequest))
        end
        def existing_pull_request(updated_dependencies)
          new_pr = PullRequest.create_from_updated_dependencies(updated_dependencies)
          job.existing_pull_requests.find { |pr| pr == new_pr }
        end
      end
    end
  end
end
