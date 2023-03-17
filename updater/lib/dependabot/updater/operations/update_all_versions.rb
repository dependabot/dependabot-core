# frozen_string_literal: true

module Dependabot
  class Updater
    module Operations
      class UpdateAllVersions
        def self.applies_to?(job:)
          return false if job.security_updates_only?
          return false if job.updating_a_pull_request?
          return false if job.dependencies&.any?

          true
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
          # TODO: Collect @created_pull_requests on the Job object?
          @created_pull_requests = []
        end

        def perform
          Dependabot.logger.info("Starting update job for #{job.source.repo}")
          dependencies.each { |dep| check_and_create_pr_with_error_handling(dep) }
        end

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler,
                    :created_pull_requests

        # rubocop:disable Metrics/PerceivedComplexity
        def dependencies
          all_deps = dependency_snapshot.dependencies

          # Tell the backend about the current dependencies on the target branch
          service.update_dependency_list(dependency_snapshot: dependency_snapshot)

          allowed_deps = all_deps.select { |d| job.allowed_update?(d) }
          # Return dependencies in a random order, with top-level dependencies
          # considered first so that dependency runs which time out don't always hit
          # the same dependencies
          allowed_deps = allowed_deps.shuffle unless ENV["UPDATER_DETERMINISTIC"]

          if all_deps.any? && allowed_deps.none?
            Dependabot.logger.info("Found no dependencies to update after filtering allowed updates")
          end

          allowed_deps
        rescue StandardError => e
          error_handler.handle_parser_error(e)
          []
        end
        # rubocop:enable Metrics/PerceivedComplexity

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

          updated_files = generate_dependency_files_for(updated_deps)
          updated_deps = updated_deps.reject do |d|
            next false if d.name == checker.dependency.name
            next true if d.top_level? && d.requirements == d.previous_requirements

            d.version == d.previous_version
          end
          create_pull_request(updated_deps, updated_files)
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def log_up_to_date(dependency)
          Dependabot.logger.info(
            "No update needed for #{dependency.name} #{dependency.version}"
          )
        end

        def raise_on_ignored?(dependency)
          job.security_updates_only? || ignore_conditions_for(dependency).any?
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
              msg += " (doesn't apply to security update)" if job.security_updates_only?
              Dependabot.logger.info(msg)
            end
          end
        end

        def name_match?(name1, name2)
          WildcardMatcher.match?(
            job.name_normaliser.call(name1),
            job.name_normaliser.call(name2)
          )
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

        def create_pull_request(dependencies, updated_dependency_files)
          Dependabot.logger.info("Submitting #{dependencies.map(&:name).join(', ')} " \
                                 "pull request for creation")

          dependency_change = Dependabot::DependencyChange.new(
            job: job,
            dependencies: dependencies,
            updated_dependency_files: updated_dependency_files
          )

          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)

          created_pull_requests << dependencies.map do |dep|
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
