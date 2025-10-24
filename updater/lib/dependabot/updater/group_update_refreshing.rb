# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/clients/github_with_retries"

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
      # - Replace existing PR if the dependencies involved have changed AND the PR hasn't been manually modified
      # - Update the existing PR if the dependencies and the target versions remain the same
      # - Supersede the existing PR if the dependencies are the same but the target versions have changed
      # - Skip update if the PR has been manually modified to preserve manual work
      sig { params(dependency_change: Dependabot::DependencyChange, group: Dependabot::DependencyGroup).void }
      def upsert_pull_request(dependency_change, group)
        if dependency_change.should_replace_existing_pr?
          # Check if the PR has been manually modified before closing it
          if pr_was_manually_modified?(group)
            Dependabot.logger.info(
              "Skipping update for '#{group.name}' group as the pull request has been manually modified. " \
              "Use '@dependabot recreate' to recreate the PR."
            )
            return
          end

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

      private

      # Checks if a grouped pull request has been manually modified by examining
      # the number of commits on the PR. A PR is considered manually modified if
      # it has more than one commit, indicating that commits beyond Dependabot's
      # original commit have been added.
      sig { params(group: Dependabot::DependencyGroup).returns(T::Boolean) }
      def pr_was_manually_modified?(group)
        return false unless job.source.provider == "github"

        pr_number = existing_pull_request_number(group)
        return false unless pr_number

        begin
          pull_request = T.let(
            T.unsafe(github_client).pull_request(job.source.repo, pr_number),
            T.untyped
          )
          # A PR with more than 1 commit indicates manual modifications
          pull_request.commits > 1
        rescue Octokit::NotFound
          # PR doesn't exist, so it hasn't been modified
          false
        end
      end

      # Extracts the PR number for an existing grouped pull request
      sig { params(group: Dependabot::DependencyGroup).returns(T.nilable(Integer)) }
      def existing_pull_request_number(group)
        existing_pr = job.existing_group_pull_requests.find do |pr|
          pr["dependency-group-name"] == group.name
        end

        return nil unless existing_pr

        # PR number can be in the dependencies or at the top level
        dependencies = existing_pr["dependencies"]
        return nil unless dependencies&.any?

        # Extract pr-number from the first dependency that has it
        dependencies.each do |dep|
          pr_number = dep["pr-number"]
          return pr_number if pr_number
        end

        nil
      end

      # Creates a GitHub client for making API requests
      sig { returns(Dependabot::Clients::GithubWithRetries) }
      def github_client
        @github_client ||= T.let(
          Dependabot::Clients::GithubWithRetries.for_source(
            source: job.source,
            credentials: job.credentials
          ),
          T.nilable(Dependabot::Clients::GithubWithRetries)
        )
      end
    end
  end
end
