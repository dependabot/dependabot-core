# typed: strict
# frozen_string_literal: true

require "dependabot/updater/operations/operation_base"

require "sorbet-runtime"

# This class implements our strategy for iterating over all of the dependencies
# for a specific project folder to find those that are out of date and create
# a single PR per Dependency.
module Dependabot
  class Updater
    module Operations
      class UpdateAllVersions < OperationBase
        extend T::Sig

        sig { override.params(job: Dependabot::Job).returns(T::Boolean) }
        def self.applies_to?(job:)
          return false if job.security_updates_only?
          return false if job.updating_a_pull_request?
          return false if job.dependencies&.any?

          true
        end

        sig { override.returns(Symbol) }
        def self.tag_name
          :update_all_versions
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
          super(service: service, job: job, dependency_snapshot: dependency_snapshot, error_handler: error_handler)
          # TODO: Collect @created_pull_requests on the Job object?
          @created_pull_requests = T.let([], T::Array[T::Hash[String, T.any(String, T::Boolean)]])

          return unless job.source.directory.nil? && T.must(job.source.directories).count == 1

          job.source.directory = T.must(job.source.directories).first
        end

        sig { override.void }
        def perform
          Dependabot.logger.info("Starting update job for #{job.source.repo}")
          Dependabot.logger.info("Checking all dependencies for version updates...")
          dependencies.each { |dep| check_and_create_pr_with_error_handling(dep) }
        end

        private

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        attr_reader :created_pull_requests

        sig { returns(T::Array[Dependency]) }
        def dependencies
          if dependency_snapshot.dependencies.any? && dependency_snapshot.allowed_dependencies.none?
            Dependabot.logger.info("Found no dependencies to update after filtering allowed updates")
            return []
          end

          if Environment.deterministic_updates?
            dependency_snapshot.ungrouped_dependencies
          else
            dependency_snapshot.ungrouped_dependencies.shuffle
          end
        end

        sig { params(dependency: Dependency).void }
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
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(dependency: Dependency).void }
        def check_and_create_pull_request(dependency)
          checker = update_checker_for(dependency, raise_on_ignored: raise_on_ignored?(dependency))

          log_checking_for_update(dependency)

          return if all_versions_ignored?(dependency, checker)
          return log_up_to_date(dependency) if checker.up_to_date?

          if pr_exists_for_latest_version?(checker)
            return Dependabot.logger.info(
              "Pull request already exists for #{checker.dependency.name} " \
              "with latest version #{checker.latest_version}"
            )
          end

          requirements_to_unlock = requirements_to_unlock(checker)
          log_requirements_for_update(requirements_to_unlock, checker)

          if requirements_to_unlock == :update_not_possible
            return Dependabot.logger.info(
              "No update possible for #{dependency.name} #{dependency.version}"
            )
          end

          updated_deps = checker.updated_dependencies(
            requirements_to_unlock: requirements_to_unlock
          )

          if updated_deps.empty?
            raise "Dependabot found some dependency requirements to unlock, yet it failed to update any dependencies"
          end

          if (existing_pr = existing_pull_request(updated_deps))
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

          if dependency_change.updated_dependency_files.empty?
            raise "UpdateChecker found viable dependencies to be updated, but FileUpdater failed to update any files"
          end

          create_pull_request(dependency_change)
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/AbcSize

        sig { params(dependency: Dependency).void }
        def log_up_to_date(dependency)
          Dependabot.logger.info(
            "No update needed for #{dependency.name} #{dependency.version}"
          )
        end

        sig { params(dependency: Dependency).returns(T::Boolean) }
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
            options: job.experiments
          )
        end

        sig { params(dependency: Dependency).void }
        def log_checking_for_update(dependency)
          Dependabot.logger.info(
            "Checking if #{dependency.name} #{dependency.version} needs updating"
          )
          job.log_ignore_conditions_for(dependency)
        end

        sig { params(dependency: Dependency, checker: UpdateCheckers::Base).returns(T::Boolean) }
        def all_versions_ignored?(dependency, checker)
          Dependabot.logger.info("Latest version is #{checker.latest_version}")
          false
        rescue Dependabot::AllVersionsIgnored
          Dependabot.logger.info("All updates for #{dependency.name} were ignored")
          true
        end

        sig { params(checker: UpdateCheckers::Base).returns(T::Boolean) }
        def pr_exists_for_latest_version?(checker)
          latest_version = checker.latest_version&.to_s
          return false if latest_version.nil?

          job.existing_pull_requests
             .select { |pr| pr.count == 1 }
             .map(&:first)
             .select { |pr| pr&.fetch("dependency-name") == checker.dependency.name }
             .any? { |pr| pr&.fetch("dependency-version", nil) == latest_version }
        end

        sig do
          params(updated_dependencies: T::Array[Dependency])
            .returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
        end
        def existing_pull_request(updated_dependencies)
          new_pr_set = T.let(
            Set.new(updated_dependencies.map do |dep|
              {
                "dependency-name" => dep.name,
                "dependency-version" => dep.version,
                "dependency-removed" => dep.removed? ? true : nil
              }.compact
            end), T::Set[T::Hash[String, T.untyped]]
          )

          result = T.let([], T::Array[T::Hash[String, T.untyped]])
          existing_prs = job.existing_pull_requests.find { |pr| Set.new(pr) == new_pr_set }
          if existing_prs.nil?
            created = created_pull_requests.find { |pr| Set.new(pr) == new_pr_set }
            result.append(created) unless created.nil?
          else
            result.concat(existing_prs)
          end

          result.count.zero? ? nil : result
        end

        sig { params(checker: UpdateCheckers::Base).returns(Symbol) }
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

        sig { params(requirements_to_unlock: Symbol, checker: UpdateCheckers::Base).void }
        def log_requirements_for_update(requirements_to_unlock, checker)
          Dependabot.logger.info("Requirements to unlock #{requirements_to_unlock}")

          return unless checker.respond_to?(:requirements_update_strategy)

          Dependabot.logger.info(
            "Requirements update strategy #{checker.requirements_update_strategy&.serialize}"
          )
        end

        # If a version update for a peer dependency is possible we should
        # defer to the PR that will be created for it to avoid duplicate PRs.
        sig { params(dependency_name: String, updated_deps: T::Array[Dependency]).returns(T::Boolean) }
        def peer_dependency_should_update_instead?(dependency_name, updated_deps)
          updated_deps
            .reject { |dep| dep.name == dependency_name }
            .any? do |dep|
              next true if existing_pull_request([dep])
              next false if dep.previous_requirements.nil?

              original_peer_dep = ::Dependabot::Dependency.new(
                name: dep.name,
                version: dep.previous_version,
                requirements: T.must(dep.previous_requirements),
                package_manager: dep.package_manager
              )
              update_checker_for(original_peer_dep, raise_on_ignored: false)
                .can_update?(requirements_to_unlock: :own)
            end
        end

        sig { params(dependency_change: DependencyChange).void }
        def create_pull_request(dependency_change)
          Dependabot.logger.info("Submitting #{dependency_change.updated_dependencies.map(&:name).join(', ')} " \
                                 "pull request for creation")

          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)

          created_prs = dependency_change.updated_dependencies.map do |dep|
            T.let({
              "dependency-name" => dep.name,
              "dependency-version" => dep.version,
              "dependency-removed" => dep.removed? ? true : nil
            }, T::Hash[String, T.untyped]).compact
          end
          created_pull_requests.concat(created_prs)
        end
      end
    end
  end
end
