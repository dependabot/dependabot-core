# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# This module contains the methods required to refresh (upsert or recreate)
# existing grouped pull requests.
#
# When included in an Operation it expects the following to be available:
# - job: the current Dependabot::Job object
# - dependency_snapshot: the Dependabot::DependencySnapshot of the current state
# - error_handler: a Dependabot::UpdaterErrorHandler to report any problems to
#
module Dependabot
  class Updater
    module GroupUpdateRefreshing
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.returns(Dependabot::Updater::ErrorHandler) }
      def error_handler; end

      sig { abstract.returns(Dependabot::Job) }
      def job; end

      sig { abstract.returns(Dependabot::DependencySnapshot) }
      def dependency_snapshot; end

      sig { abstract.returns(Dependabot::Service) }
      def service; end

      sig { params(dependency_change: Dependabot::DependencyChange, group: Dependabot::DependencyGroup).void }
      def upsert_pull_request_with_error_handling(dependency_change, group)
        if dependency_change.updated_dependencies.any?
          upsert_pull_request(dependency_change, group)
        elsif pr_exists_and_is_up_to_date?(dependency_change, group)
          Dependabot.logger.info("Pull request already up-to-date for '#{group.name}'")
          # The PR is already up-to-date, so we update it with a no-op to refresh metadata
          service.update_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
        else
          Dependabot.logger.info("No updated dependencies, closing existing Pull Request")
          close_pull_request(reason: :update_no_longer_possible, group: group)
        end
      rescue StandardError => e
        error_handler.handle_job_error(error: e, dependency_group: dependency_snapshot.job_group)
      ensure
        # record metrics for the ecosystem
        service.record_ecosystem_meta(dependency_snapshot.ecosystem)
      end

      # Having created the dependency_change, we need to determine the right strategy to apply it to the project:
      # - Replace existing PR if the dependencies involved have changed
      # - Update the existing PR if the dependencies and the target versions remain the same
      # - Supersede the existing PR if the dependencies are the same but the target versions have changed
      sig { params(dependency_change: Dependabot::DependencyChange, group: Dependabot::DependencyGroup).void }
      def upsert_pull_request(dependency_change, group)
        if dependency_change.should_replace_existing_pr?
          Dependabot.logger.info("Dependencies have changed, closing existing Pull Request")
          close_pull_request(reason: :dependencies_changed, group: group)
          Dependabot.logger.info("Creating a new pull request for '#{group.name}'")
          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
        elsif dependency_change.matches_existing_pr?
          Dependabot.logger.info("Updating pull request for '#{group.name}'")
          service.update_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
        else
          # If the changes do not match an existing PR, then we should open a new pull request and leave it to
          # the backend to close the existing pull request with a comment that it has been superseded.
          Dependabot.logger.info("Target versions have changed, existing Pull Request should be superseded")
          Dependabot.logger.info("Creating a new pull request for '#{group.name}'")
          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)
        end
      end

      sig { params(reason: Symbol, group: Dependabot::DependencyGroup).void }
      def close_pull_request(reason:, group:)
        reason_string = reason.to_s.tr("_", " ")
        Dependabot.logger.info(
          "Telling backend to close pull request for the " \
          "#{group.name} group " \
          "(#{job.dependencies&.join(', ')}) - #{reason_string}"
        )

        service.close_pull_request(T.must(job.dependencies), reason)
      end

      # Checks if an existing PR for the group still represents needed updates
      # Returns true if:
      # - A PR exists for the group
      # - All dependencies in the PR are still present in the project and in the group
      # - The main branch is NOT yet at the PR's target versions (updates are still needed)
      # 
      # Returns false if dependencies have been updated externally to match the PR
      sig { params(dependency_change: Dependabot::DependencyChange, group: Dependabot::DependencyGroup).returns(T::Boolean) }
      def pr_exists_and_is_up_to_date?(dependency_change, group)
        # Check if there's an existing PR for this group
        existing_pr = job.existing_group_pull_requests.find do |pr|
          T.cast(pr["dependency-group-name"], T.nilable(String)) == group.name
        end

        return false unless existing_pr

        # Get dependencies from the existing PR
        pr_dependencies = T.cast(existing_pr["dependencies"], T.nilable(T::Array[T::Hash[String, T.untyped]])) || []
        return false if pr_dependencies.empty?

        # Check if the PR is still needed by verifying dependencies haven't been updated externally
        pr_dependencies.all? do |pr_dep|
          dep_name = T.cast(pr_dep["dependency-name"], T.nilable(String))
          pr_target_version = T.cast(pr_dep["dependency-version"], T.nilable(String))

          next false unless dep_name && pr_target_version

          # Find the dependency in the current snapshot
          current_dep = dependency_snapshot.dependencies.find { |d| d.name == dep_name }

          # If dependency is not found, the PR is no longer valid
          next false unless current_dep

          # Check if the dependency is still in the group
          next false unless group.dependencies.any? { |d| d.name == dep_name }

          # If current version equals PR target, dependencies were updated externally
          # The PR is no longer needed and should be closed
          next false if current_dep.version.to_s == pr_target_version

          # The dependency is still at an older version, so the PR is still needed
          # Keep the PR open even if no new updates are available
          true
        end
      end
    end
  end
end
