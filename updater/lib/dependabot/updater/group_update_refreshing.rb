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

      sig { abstract.params(group: Dependabot::DependencyGroup).returns(T.nilable(Dependabot::Job::ExistingGroupPullRequest)) }
      def find_existing_group_pr(group); end

      sig { params(dependency_change: Dependabot::DependencyChange, group: Dependabot::DependencyGroup).void }
      def upsert_pull_request_with_error_handling(dependency_change, group)
        if dependency_change.updated_dependencies.any?
          upsert_pull_request(dependency_change, group)
        elsif existing_pr_deferred_by_cooldown?(group)
          Dependabot.logger.info(
            "No updated dependencies because a newer release is in its cooldown period; " \
            "keeping existing Pull Request open"
          )
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

      # A refresh that finds nothing to update normally means the PR is obsolete. When every dependency in the
      # existing PR has a newer candidate that was only withheld by cooldown, the proposal is still valid (it was
      # created under the same cooldown) so keep it. The PR's target digest is not recorded in the job
      # definition, so it cannot be compared against the repository here.
      sig { params(group: Dependabot::DependencyGroup).returns(T::Boolean) }
      def existing_pr_deferred_by_cooldown?(group)
        pr_dependencies = (find_existing_group_pr(group)&.dependencies || []).reject(&:removed)
        return false if pr_dependencies.empty?

        pr_dependencies.all? { |pr_dep| pr_dependency_deferred_by_cooldown?(pr_dep) }
      end

      sig { params(pr_dep: Dependabot::Job::ExistingGroupPullRequest::Dependency).returns(T::Boolean) }
      def pr_dependency_deferred_by_cooldown?(pr_dep)
        return false unless pr_dep.name

        directory = pr_dep.directory
        candidates = if directory
                       dependency_snapshot.dependencies_in_directory(directory)
                     else
                       dependency_snapshot.all_dependencies
                     end

        candidates.any? do |dep|
          dep.name == pr_dep.name &&
            Dependabot::UpdateCheckers::CooldownCalculation.update_deferred?(dep) &&
            !pr_target_older_than_current?(dep, pr_dep)
        end
      end

      # Equal versions are allowed (digest-only refreshes); a PR target provably older than the version now on
      # the base branch would downgrade it, so it must not be retained.
      sig do
        params(dep: Dependabot::Dependency, pr_dep: Dependabot::Job::ExistingGroupPullRequest::Dependency)
          .returns(T::Boolean)
      end
      def pr_target_older_than_current?(dep, pr_dep)
        current = dep.version
        target = pr_dep.version
        return false unless current && target

        version_class = Dependabot::Utils.version_class_for_package_manager(dep.package_manager)
        return false unless version_class.correct?(current) && version_class.correct?(target)

        version_class.new(target) < version_class.new(current)
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
