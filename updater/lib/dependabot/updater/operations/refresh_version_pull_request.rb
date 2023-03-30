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
      class RefreshVersionPullRequest
        def self.applies_to?(job:)
          return false if job.security_updates_only?
          # If we haven't been given metadata about the dependencies present
          # in the pull request, this strategy cannot act.
          return false if job.dependencies&.none?

          job.updating_a_pull_request?
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
          all_deps = dependency_snapshot.dependencies

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
            Dependabot.logger.info("Found no dependencies to update after filtering allowed " \
                                   "updates")
          end

          allowed_deps
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        #
        # TODO: Push checks on dependencies into Dependabot::DependencyChange
        #
        # Some of this logic would make more sense as interrogations of the
        # DependencyChange as we build it up step-by-step.
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
            create_pull_request(updated_deps, updated_files)
          elsif existing_pull_request(updated_deps)
            # The existing PR is for this version. Update it.
            update_pull_request(updated_deps, updated_files)
          else
            # The existing PR is for a previous version. Supersede it.
            create_pull_request(updated_deps, updated_files)
          end
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        def create_pull_request(dependencies, updated_dependency_files)
          Dependabot.logger.info("Submitting #{dependencies.map(&:name).join(', ')} " \
                                 "pull request for creation")

          dependency_change = Dependabot::DependencyChange.new(
            job: job,
            dependencies: dependencies,
            updated_dependency_files: updated_dependency_files
          )

          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
        end

        def update_pull_request(dependencies, updated_dependency_files)
          Dependabot.logger.info("Submitting #{dependencies.map(&:name).join(', ')} " \
                                 "pull request for update")

          dependency_change = Dependabot::DependencyChange.new(
            job: job,
            dependencies: dependencies,
            updated_dependency_files: updated_dependency_files
          )

          service.update_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
        end

        def close_pull_request(reason:)
          reason_string = reason.to_s.tr("_", " ")
          Dependabot.logger.info("Telling backend to close pull request for " \
                                 "#{job.dependencies.join(', ')} - #{reason_string}")
          service.close_pull_request(job.dependencies, reason)
        end

        def raise_on_ignored?(dependency)
          ignore_conditions_for(dependency).any?
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
            ignored_versions_for(dep, security_updates_only: false)
        end

        def update_checker_for(dependency, raise_on_ignored:)
          Dependabot::UpdateCheckers.for_package_manager(job.package_manager).new(
            dependency: dependency,
            dependency_files: dependency_snapshot.dependency_files,
            repo_contents_path: job.repo_contents_path,
            credentials: job.credentials,
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
            dependency_files: dependency_snapshot.dependency_files,
            repo_contents_path: job.repo_contents_path,
            credentials: job.credentials,
            options: job.experiments
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

        def log_checking_for_update(dependency)
          Dependabot.logger.info(
            "Checking if #{dependency.name} #{dependency.version} needs updating"
          )
          log_ignore_conditions(dependency)
        end

        def log_ignore_conditions(dep)
          conditions = job.ignore_conditions.
                       select { |ic| name_match?(ic["dependency-name"], dep.name) }
          return if conditions.empty?

          Dependabot.logger.info("Ignored versions:")
          conditions.each do |ic|
            unless ic["version-requirement"].nil?
              Dependabot.logger.info("  #{ic['version-requirement']} - from #{ic['source']}")
            end

            ic["update-types"]&.each do |update_type|
              msg = "  #{update_type} - from #{ic['source']}"
              Dependabot.logger.info(msg)
            end
          end
        end

        def all_versions_ignored?(dependency, checker)
          Dependabot.logger.info("Latest version is #{checker.latest_version}")
          false
        rescue Dependabot::AllVersionsIgnored
          Dependabot.logger.info("All updates for #{dependency.name} were ignored")
          true
        end

        def name_match?(name1, name2)
          WildcardMatcher.match?(
            job.name_normaliser.call(name1),
            job.name_normaliser.call(name2)
          )
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

        def generate_dependency_files_for(updated_dependencies)
          if updated_dependencies.count == 1
            updated_dependency = updated_dependencies.first
            Dependabot.logger.info("Updating #{updated_dependency.name} from " \
                                   "#{updated_dependency.previous_version} to " \
                                   "#{updated_dependency.version}")
          else
            dependency_names = updated_dependencies.map(&:name)
            Dependabot.logger.info("Updating #{dependency_names.join(', ')}")
          end

          # Ignore dependencies that are tagged as information_only. These will be
          # updated indirectly as a result of a parent dependency update and are
          # only included here to be included in the PR info.
          deps_to_update = updated_dependencies.reject(&:informational_only?)
          updater = file_updater_for(deps_to_update)
          updater.updated_dependency_files
        end
      end
    end
  end
end
