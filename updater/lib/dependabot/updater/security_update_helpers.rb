# typed: true
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

      sig { returns(Dependabot::Service) }
      attr_reader :service

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
          checker.lowest_security_fix_version.to_s
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
            "dependency-removed": dep.removed? ? true : nil
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
        if lowest_non_vulnerable_version
          "The earliest fixed version is #{lowest_non_vulnerable_version}."
        else
          "Dependabot could not find a non-vulnerable version"
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

      sig { returns(Dependabot::Service) }
      attr_reader :service

      abstract!

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

      # Resurns unique warning notices which are going to be shown on insight page.
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
    end
  end
end
