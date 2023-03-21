# frozen_string_literal: true

module Dependabot
  class Updater
    module Operations
      class GroupUpdateAllVersions
        GROUP_NAME_PLACEHOLDER = "*"

        def self.applies_to?(job:)
          return false if job.security_updates_only?
          return false if job.updating_a_pull_request?
          return false if job.dependencies&.any?

          Dependabot::Experiments.enabled?(:grouped_updates_prototype)
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
        end

        def perform
          Dependabot.logger.info("[Experimental] Starting grouped update job for #{job.source.repo}")
          # We should log the rule being executed, let's just hard-code wildcard for now
          # since the prototype makes best-effort to do everything in one pass.
          Dependabot.logger.info("Starting update group for '#{GROUP_NAME_PLACEHOLDER}'")
          dependency_change = compile_dependency_change

          if dependency_change.dependencies.any?
            Dependabot.logger.info("Creating a pull request for '#{GROUP_NAME_PLACEHOLDER}'")
            begin
              service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
            rescue StandardError => e
              # FIXME: This is a workround for not having a single Dependency to report against
              #
              #        We could use all_updated_deps.first, but that could be misleading. It may
              #        make more sense to handle the group rule as a Dependancy-ish object
              group_dependency = OpenStruct.new(name: "group-all")
              raise if ErrorHandler::RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

              error_handler.handle_dependabot_error(error: e, dependency: group_dependency)
            end
          else
            Dependabot.logger.info("Nothing to update for Group Rule: '#{GROUP_NAME_PLACEHOLDER}'")
          end
        end

        private

        attr_reader :job,
                    :service,
                    :dependency_snapshot,
                    :error_handler

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

        # Returns a Dependabot::DependencyChange object that encapsulates the
        # outcome of attempting to update every dependency iteratively which
        # can be used for PR creation.
        def compile_dependency_change
          all_updated_dependencies = []
          updated_files = dependencies.inject(dependency_snapshot.dependency_files) do |dependency_files, dependency|
            updated_dependencies = compile_updates_for(dependency, dependency_files)

            if updated_dependencies.any?
              lead_dependency = updated_dependencies.find do |dep|
                dep.name.casecmp(dependency.name).zero?
              end

              # FIXME: This needs to be de-duped
              #
              # To start out with, using a variant on the 'existing_pull_request'
              # logic might make sense -or- we could employ a one-and-done rule
              # where the first update to a dependency blocks subsequent changes.
              #
              # In a follow-up iteration, a 'shared workspace' could provide the
              # filtering for us assuming we iteratively make file changes for
              # each Array of dependencies in the batch and the FileUpdater tells
              # us which cannot be applied.
              all_updated_dependencies.concat(updated_dependencies)
              generate_dependency_files_for(lead_dependency, updated_dependencies, dependency_files)
            else
              dependency_files # pass on the existing files if no updates are possible
            end
          end

          Dependabot::DependencyChange.new(
            job: job,
            dependencies: all_updated_dependencies,
            updated_dependency_files: updated_files
          )
        end

        # This method determines which dependencies must change given a target
        # 'lead' dependency we want to update.
        #
        # This may return more than 1 dependency since the ecosystem-specific
        # tooling may find collaborators which need to be updated in lock-step.
        #
        # This method **must** must return an Array when it errors
        def compile_updates_for(dependency, dependency_files)
          checker = update_checker_for(dependency, dependency_files, raise_on_ignored: raise_on_ignored?(dependency))

          log_checking_for_update(dependency)

          # FIXME: Grouped updates currently do not interact with ignore rules
          # return [] if all_versions_ignored?(dependency, checker)

          if checker.up_to_date?
            log_up_to_date(dependency)
            return []
          end

          requirements_to_unlock = requirements_to_unlock(checker)
          log_requirements_for_update(requirements_to_unlock, checker)

          if requirements_to_unlock == :update_not_possible
            Dependabot.logger.info(
              "No update possible for #{dependency.name} #{dependency.version}"
            )
            return []
          end

          updated_deps = checker.updated_dependencies(
            requirements_to_unlock: requirements_to_unlock
          )

          if peer_dependency_should_update_instead?(checker.dependency.name, updated_deps)
            Dependabot.logger.info(
              "No update possible for #{dependency.name} #{dependency.version} (peer dependency can be updated)"
            )
            return []
          end

          filter_unrelated_and_unchanged(updated_deps, checker)
        rescue Dependabot::InconsistentRegistryResponse => e
          error_handler.log_error(
            dependency: dependency,
            error: e,
            error_type: "inconsistent_registry_response",
            error_detail: e.message
          )
          [] # return an empty set
        rescue StandardError => e
          error_handler.handle_dependabot_error(error: e, dependency: dependency)
          [] # return an empty set
        end

        def filter_unrelated_and_unchanged(updated_dependencies, checker)
          updated_dependencies.reject do |d|
            next false if d.name == checker.dependency.name
            next true if d.top_level? && d.requirements == d.previous_requirements

            d.version == d.previous_version
          end
        end

        def log_up_to_date(dependency)
          Dependabot.logger.info(
            "No update needed for #{dependency.name} #{dependency.version}"
          )
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

        def update_checker_for(dependency, dependency_files, raise_on_ignored:)
          Dependabot::UpdateCheckers.for_package_manager(job.package_manager).new(
            dependency: dependency,
            dependency_files: dependency_files,
            repo_contents_path: job.repo_contents_path,
            credentials: job.credentials,
            ignored_versions: [], # FIXME: Grouped updates do not honour ignore rules for now
            security_advisories: [], # FIXME: Version updates do not use advisory data for now
            raise_on_ignored: raise_on_ignored,
            requirements_update_strategy: job.requirements_update_strategy,
            options: job.experiments
          )
        end

        def file_updater_for(dependencies, dependency_files)
          Dependabot::FileUpdaters.for_package_manager(job.package_manager).new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: job.repo_contents_path,
            credentials: job.credentials,
            options: job.experiments
          )
        end

        def log_checking_for_update(dependency)
          Dependabot.logger.info(
            "Checking if #{dependency.name} #{dependency.version} needs updating"
          )
          # FIXME: Grouped updates do not honour ignore rules for now
          # log_ignore_conditions(dependency)
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
          true
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
          updated_deps.
            reject { |dep| dep.name == dependency_name }.
            any? do |dep|
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

        # This method generates new dependency files from the current files and list of dependencies to
        # be updated
        #
        # This method **must** return the current files in the event of an error
        def generate_dependency_files_for(lead_dependency, updated_dependencies, current_dependency_files)
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
          updater = file_updater_for(deps_to_update, current_dependency_files)
          updater.updated_dependency_files
        rescue Dependabot::InconsistentRegistryResponse => e
          error_handler.log_error(
            dependency: lead_dependency,
            error: e,
            error_type: "inconsistent_registry_response",
            error_detail: e.message
          )
          current_dependency_files # return the files unchanged
        rescue StandardError => e
          raise if ErrorHandler::RUN_HALTING_ERRORS.keys.any? { |err| e.is_a?(err) }

          error_handler.handle_dependabot_error(error: e, dependency: lead_dependency)
          current_dependency_files # return the files unchanged
        end
      end
    end
  end
end
