# typed: strong
# frozen_string_literal: true

require "dependabot/updater/security_update_helpers"
require "dependabot/notices"

# This class implements our strategy for iterating over all of the dependencies
# for a specific project folder to find those that are out of date and create
# a single PR per Dependency.
module Dependabot
  class Updater
    module Operations
      class UpdateAllVersions
        extend T::Sig
        include PullRequestHelpers

        sig { params(_job: Dependabot::Job).returns(T::Boolean) }
        def self.applies_to?(_job:)
          false # only called elsewhere
        end

        sig { returns(Symbol) }
        def self.tag_name
          :update_all_versions
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
          # TODO: Collect @created_pull_requests on the Job object?
          @created_pull_requests = T.let([], T::Array[PullRequest])

          @notices = T.let([], T::Array[Dependabot::Notice])

          return unless job.source.directory.nil? && job.source.directories&.count == 1

          job.source.directory = job.source.directories&.first
        end

        sig { void }
        def perform
          Dependabot.logger.info("Starting update job for #{job.source.repo}")
          Dependabot.logger.info("Checking all dependencies for version updates...")

          # Add a deprecation notice if the package manager is deprecated
          add_deprecation_notice(
            notices: @notices,
            package_manager: dependency_snapshot.package_manager
          )

          dependencies.each { |dep| check_and_create_pr_with_error_handling(dep) }
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

        sig { returns(T::Array[Dependabot::Dependency]) }
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

        sig { params(dependency: Dependabot::Dependency).void }
        def check_and_create_pr_with_error_handling(dependency)
          check_and_create_pull_request(dependency)
        rescue URI::InvalidURIError => e
          error_handler.handle_dependency_error(error: Dependabot::DependencyFileNotResolvable.new(e.message),
                                                dependency: dependency)
        rescue Dependabot::InconsistentRegistryResponse => e
          error_handler.log_dependency_error(
            dependency: dependency,
            error: e,
            error_type: "inconsistent_registry_response",
            error_detail: e.message
          )
        rescue StandardError => e
          process_dependency_error(e, dependency)
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(dependency: Dependabot::Dependency).void }
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
            change_source: checker.dependency,
            notices: @notices
          )

          if dependency_change.updated_dependency_files.empty?
            raise "UpdateChecker found viable dependencies to be updated, but FileUpdater failed to update any files"
          end

          # Record any warning notices that were generated during the update process if conditions are met
          record_warning_notices(@notices)

          create_pull_request(dependency_change)
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/AbcSize

        sig { params(dependency: Dependabot::Dependency).void }
        def log_up_to_date(dependency)
          Dependabot.logger.info(
            "No update needed for #{dependency.name} #{dependency.version}"
          )
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

        sig { params(error: StandardError, dependency: Dependabot::Dependency).returns(T.untyped) }
        def process_dependency_error(error, dependency)
          if error.class.to_s.include?("RegistryError")
            ex = Dependabot::DependencyFileNotResolvable.new(error.message)
            error_handler.handle_dependency_error(error: ex, dependency: dependency)
          else
            error_handler.handle_dependency_error(error: error, dependency: dependency)
          end
        end

        sig do
          params(dependency: Dependabot::Dependency, checker: Dependabot::UpdateCheckers::Base)
            .returns(T::Boolean)
        end
        def all_versions_ignored?(dependency, checker)
          Dependabot.logger.info("Latest version is #{checker.latest_version}")
          false
        rescue Dependabot::AllVersionsIgnored
          Dependabot.logger.info("All updates for #{dependency.name} were ignored")
          true
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
            .returns(T.nilable(Dependabot::PullRequest))
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

        sig { params(requirements_to_unlock: Symbol, checker: Dependabot::UpdateCheckers::Base).void }
        def log_requirements_for_update(requirements_to_unlock, checker)
          Dependabot.logger.info("Requirements to unlock #{requirements_to_unlock}")

          return unless checker.respond_to?(:requirements_update_strategy)

          Dependabot.logger.info(
            "Requirements update strategy #{checker.requirements_update_strategy&.serialize}"
          )
        end

        # If a version update for a peer dependency is possible we should
        # defer to the PR that will be created for it to avoid duplicate PRs.
        sig { params(dependency_name: String, updated_deps: T::Array[Dependabot::Dependency]).returns(T::Boolean) }
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
