# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# This module extracts all helpers required to perform additional update job
# error recording and logging for Security Updates since they are shared
# between a few operations.
module Dependabot
  class Updater
    module SecurityUpdateHelpers
      extend T::Sig
      extend T::Helpers

      abstract!

      private

      sig { abstract.returns(Dependabot::Service) }
      def service; end

      public

      sig { params(dependency: Dependabot::Dependency).void }
      def record_security_update_not_needed_error(dependency)
        Dependabot.logger.info(
          "no security update needed as #{dependency.name} " \
          "is no longer vulnerable"
        )

        service.record_update_job_error(
          error_type: "security_update_not_needed",
          error_details: {
            "dependency-name": dependency.name
          }
        )
      end

      sig { params(checker: Dependabot::UpdateCheckers::Base).void }
      def record_security_update_ignored(checker)
        Dependabot.logger.info(
          "Dependabot cannot update to the required version as all versions " \
          "were ignored for #{checker.dependency.name}"
        )

        service.record_update_job_error(
          error_type: "all_versions_ignored",
          error_details: {
            "dependency-name": checker.dependency.name
          }
        )
      end

      sig { params(checker: Dependabot::UpdateCheckers::Base).void }
      def record_dependency_file_not_supported_error(checker)
        Dependabot.logger.info(
          "Dependabot can't update vulnerable dependencies for projects " \
          "without a lockfile or pinned version requirement as the currently " \
          "installed version of #{checker.dependency.name} isn't known."
        )

        service.record_update_job_error(
          error_type: "dependency_file_not_supported",
          error_details: {
            "dependency-name": checker.dependency.name
          }
        )
      end

      sig { params(checker: Dependabot::UpdateCheckers::Base).void }
      def record_security_update_not_possible_error(checker)
        latest_allowed_version =
          (checker.lowest_resolvable_security_fix_version ||
           checker.dependency.version)&.to_s
        lowest_non_vulnerable_version =
          checker.lowest_security_fix_version&.to_s
        conflicting_dependencies = checker.conflicting_dependencies

        Dependabot.logger.info(
          security_update_not_possible_message(checker, T.must(latest_allowed_version), conflicting_dependencies)
        )
        Dependabot.logger.info(
          earliest_fixed_version_message(lowest_non_vulnerable_version)
        )

        service.record_update_job_error(
          error_type: "security_update_not_possible",
          error_details: {
            "dependency-name": checker.dependency.name,
            "latest-resolvable-version": latest_allowed_version,
            "lowest-non-vulnerable-version": lowest_non_vulnerable_version,
            "conflicting-dependencies": conflicting_dependencies
          }
        )
      end

      sig { params(checker: Dependabot::UpdateCheckers::Base).void }
      def record_security_update_not_found(checker)
        Dependabot.logger.info(
          "Dependabot can't find a published or compatible non-vulnerable " \
          "version for #{checker.dependency.name}. " \
          "The latest available version is #{checker.dependency.version}"
        )

        service.record_update_job_error(
          error_type: "security_update_not_found",
          error_details: {
            "dependency-name": checker.dependency.name,
            "dependency-version": checker.dependency.version
          },
          dependency: checker.dependency
        )
      end

      sig { params(checker: Dependabot::UpdateCheckers::Base).void }
      def record_pull_request_exists_for_latest_version(checker)
        service.record_update_job_error(
          error_type: "pull_request_exists_for_latest_version",
          error_details: {
            "dependency-name": checker.dependency.name,
            "dependency-version": checker.latest_version&.to_s
          },
          dependency: checker.dependency
        )
      end

      sig { params(existing_pull_request: PullRequest).void }
      def record_pull_request_exists_for_security_update(existing_pull_request)
        updated_dependencies = existing_pull_request.dependencies.map do |dep|
          {
            "dependency-name": dep.name,
            "dependency-version": dep.version,
            "dependency-removed": dep.removed? || nil
          }.compact
        end

        service.record_update_job_error(
          error_type: "pull_request_exists_for_security_update",
          error_details: {
            "updated-dependencies": updated_dependencies
          }
        )
      end

      sig { void }
      def record_security_update_dependency_not_found
        service.record_update_job_error(
          error_type: "security_update_dependency_not_found",
          error_details: {}
        )
      end

      sig { params(lowest_non_vulnerable_version: T.nilable(String)).returns(String) }
      def earliest_fixed_version_message(lowest_non_vulnerable_version)
        if lowest_non_vulnerable_version && !lowest_non_vulnerable_version.empty?
          "The earliest fixed version is #{lowest_non_vulnerable_version}."
        else
          "Dependabot could not find an allowed non-vulnerable version"
        end
      end

      sig do
        params(
          checker: Dependabot::UpdateCheckers::Base,
          latest_allowed_version: String,
          conflicting_dependencies: T::Array[T::Hash[String, String]]
        )
          .returns(String)
      end
      def security_update_not_possible_message(checker, latest_allowed_version, conflicting_dependencies)
        if conflicting_dependencies.any?
          dep_messages = conflicting_dependencies.map do |dep|
            "  #{dep['explanation']}"
          end.join("\n")

          dependencies_pluralized =
            conflicting_dependencies.count > 1 ? "dependencies" : "dependency"

          "The latest possible version that can be installed is " \
            "#{latest_allowed_version} because of the following " \
            "conflicting #{dependencies_pluralized}:\n\n#{dep_messages}"
        else
          "The latest possible version of #{checker.dependency.name} that can " \
            "be installed is #{latest_allowed_version}"
        end
      end
    end

    module PullRequestHelpers
      extend T::Sig
      extend T::Helpers

      abstract!

      # Curated `operation` tag values shared by the `blocked_versions.*` metrics.
      # Defined once here so the "soft" (ignored) per-operation call sites and the
      # "hard" (enforced) ErrorHandler translation stay in lockstep on one label
      # set rather than re-listing the same strings in two places.
      module BlockedVersionsOperation
        VERSION_UPDATE = T.let("version_update", String)
        SECURITY_UPDATE = T.let("security_update", String)
        REFRESH_SECURITY_UPDATE = T.let("refresh_security_update", String)
        REFRESH_VERSION_UPDATE = T.let("refresh_version_update", String)
        GROUP_UPDATE = T.let("group_update", String)
      end

      private

      sig { abstract.returns(Dependabot::Service) }
      def service; end

      public

      sig { params(notices: T.nilable(T::Array[Dependabot::Notice])).void }
      def record_warning_notices(notices)
        return if !notices || notices.empty?

        # Find unique warning notices which are going to be shown on insight page.
        warn_notices = unique_warn_notices(notices)

        warn_notices.each do |notice|
          # If alert is enabled, sending the deprecation notice to the service for showing on the UI insight page
          send_alert_notice(notice) if notice.show_alert
        end
      rescue StandardError => e
        Dependabot.logger.error(
          "Failed to send notice warning: #{e.message}"
        )
      end

      private

      # Returns unique warning notices which are going to be shown on insight page.
      sig { params(notices: T::Array[Dependabot::Notice]).returns(T::Array[Dependabot::Notice]) }
      def unique_warn_notices(notices)
        notices
          .select { |notice| notice.mode == Dependabot::Notice::NoticeMode::WARN }
          .uniq { |notice| [notice.type, notice.package_manager_name] }
      end

      sig { params(notice: Dependabot::Notice).void }
      def send_alert_notice(notice)
        # Sending the notice to the service for showing on the dependabot insight page
        service.record_update_job_warning(
          warn_type: notice.type,
          warn_title: notice.title,
          warn_description: notice.description
        )
      end

      # Emits a counter when a GitHub Security blocklist entry applies to a
      # dependency Core is actively checking for updates.
      #
      # This is the "soft" block status. When a block applies, the blocked
      # versions are folded into the resolver's ignore conditions so they can't
      # be selected - but they sit alongside the user's own ignores (dependabot.yml
      # ignore rules and allow update-types), all merged into `ignore_conditions_for`.
      # Because of that merge, the downstream `AllVersionsIgnored` outcome can't be
      # attributed to blocking vs ignoring without re-resolving. We therefore only
      # measure the one block-specific fact Core can observe cleanly: that a Security
      # block was in effect for this dependency check (presence), not that it
      # excluded a specific candidate version (causation).
      #
      # This pairs with the "hard" status `blocked_versions.enforced` (the
      # transitive-enforcement path that rejects PR creation) under the shared
      # `blocked_versions.*` namespace.
      sig { params(job: Dependabot::Job, dependency: Dependabot::Dependency, operation: String).void }
      def record_blocked_version_ignored(job:, dependency:, operation:)
        return unless job.blocked_versions_for?(dependency)

        record_blocked_versions_metric(status: "ignored", job: job, operation: operation)
      end

      # Emits a counter when a GitHub Security blocklist entry causes a selected
      # update to be rejected outright: regenerating the lockfile would have
      # introduced a blocked transitive version, so the whole change is dropped.
      #
      # This is the "hard" block status. It pairs with the "soft" status
      # `blocked_versions.ignored` (recorded at check time when a block is folded
      # into the resolver's ignore conditions) under the shared `blocked_versions.*`
      # namespace, so the two correlate cleanly on the service side.
      sig { params(job: Dependabot::Job, operation: String).void }
      def record_blocked_version_enforced(job:, operation:)
        record_blocked_versions_metric(status: "enforced", job: job, operation: operation)
      end

      # Shared emitter for the `blocked_versions.*` counter family. Both the
      # "soft" (ignored) and "hard" (enforced) statuses report the same
      # `operation` and `package_manager` dimensions, differing only in the
      # status suffix, so callers correlate cleanly on the service side.
      sig { params(status: String, job: Dependabot::Job, operation: String).void }
      def record_blocked_versions_metric(status:, job:, operation:)
        service.increment_metric(
          "blocked_versions.#{status}",
          tags: {
            operation: operation,
            package_manager: job.package_manager
          }
        )
      end
    end
  end
end
