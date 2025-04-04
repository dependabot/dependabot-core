# typed: true
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

      sig { returns(Dependabot::Service) }
      attr_reader :service

      sig { returns(Dependabot::Updater::ErrorHandler) }
      attr_reader :error_handler

      sig { returns(Dependabot::Job) }
      attr_reader :job

      sig { returns(Dependabot::DependencySnapshot) }
      attr_reader :dependency_snapshot

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
    end
  end
end
