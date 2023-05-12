# frozen_string_literal: true

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
        def self.applies_to?(job:)
          return false if job.security_updates_only?
          # If we haven't been given metadata about the dependencies present
          # in the pull request, this strategy cannot act.
          return false if job.dependencies&.none?

          job.updating_a_pull_request?
        end

        def self.tag_name
          :update_version_pr
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
        end

        def perform
          Dependabot.logger.info("Starting PR update job for #{job.source.repo}")
          dependency = dependencies.last
          check_and_update_pull_request(dependencies)
        rescue StandardError => e
          error_handler.handle_dependabot_error(error: e, dependency: dependency)
        end

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler,
                    :created_pull_requests

        def dependencies
          dependency_snapshot.job_dependencies
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        def check_and_update_pull_request(dependencies)
          if dependencies.count != job.dependencies.count
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
            change_source: checker.dependency
          )

          # NOTE: Gradle, Maven and Nuget dependency names can be case-insensitive
          # and the dependency name in the security advisory often doesn't match
          # what users have specified in their manifest.
          job_dependencies = job.dependencies.map(&:downcase)
          if dependency_change.updated_dependencies.map(&:name).map(&:downcase) != job_dependencies
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

        def create_pull_request(dependency_change)
          Dependabot.logger.info("Submitting #{dependency_change.updated_dependencies.map(&:name).join(', ')} " \
                                 "pull request for creation")

          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
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

        def raise_on_ignored?(dependency)
          job.ignore_conditions_for(dependency).any?
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

          job.existing_pull_requests.find { |pr| Set.new(pr) == new_pr_set }
        end
      end
    end
  end
end
