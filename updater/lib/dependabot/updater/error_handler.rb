# typed: strict
# frozen_string_literal: true

require "dependabot/errors"
require "dependabot/updater/errors"
require "octokit"
require "sorbet-runtime"

# This class is responsible for determining how to present a Dependabot::Error
# to the Service and Logger.
#
# TODO: Iterate further on leaner error handling
#
# This class is a coarse abstraction of some shared logic that has several flags
# against it from Rubocop we aren't addressing right now.
#
# It feels like this concern could be slimmed down if each Dependabot::Error
# class implemented a "presenter" method to generate it's own `error-type` and
# `error-detail` since this never draws attributes from the Updater context.
#
# For now, let's just extract it and set it aside as a tangent from the critical
# path.
module Dependabot
  class Updater
    class ErrorHandler
      extend T::Sig

      # These are errors that halt the update run and are handled in the main
      # backend. They do *not* raise a sentry.
      RUN_HALTING_ERRORS = T.let({
        Dependabot::OutOfDisk => "out_of_disk",
        Dependabot::OutOfMemory => "out_of_memory",
        Dependabot::AllVersionsIgnored => "all_versions_ignored",
        Dependabot::UnexpectedExternalCode => "unexpected_external_code",
        Errno::ENOSPC => "out_of_disk",
        Octokit::Unauthorized => "octokit_unauthorized"
      }.freeze, T::Hash[T.class_of(Exception), String])

      sig { params(service: Service, job: Job).void }
      def initialize(service:, job:)
        @service = service
        @job = job
      end

      # This method handles errors where there is a dependency in the current
      # context. This should be used by preference where possible.
      sig do
        params(
          error: StandardError,
          dependency: T.nilable(Dependency),
          dependency_group: T.nilable(DependencyGroup)
        ).void
      end
      def handle_dependency_error(error:, dependency:, dependency_group: nil)
        # If the error is fatal for the run, we should re-raise it rather than
        # pass it back to the service.
        raise error if RUN_HALTING_ERRORS.keys.any? { |err| error.is_a?(err) }

        error_details = error_details_for(error, dependency: dependency, dependency_group: dependency_group)
        service.record_update_job_error(
          error_type: error_details.fetch(:"error-type"),
          error_details: error_details[:"error-detail"],
          dependency: dependency
        )
        # We don't set this flag in GHES because there older GHES version does not support reporting unknown errors.
        if Experiments.enabled?(:record_update_job_unknown_error) &&
           error_details.fetch(:"error-type") == "unknown_error"
          log_unknown_error_with_backtrace(error)
        end

        log_dependency_error(
          dependency: dependency,
          error: error,
          error_type: error_details.fetch(:"error-type"),
          error_detail: error_details.fetch(:"error-detail", nil)
        )
      end

      # Provides logging for errors that occur when processing a dependency
      sig do
        params(
          dependency: T.nilable(Dependabot::Dependency),
          error: StandardError,
          error_type: String,
          error_detail: T.nilable(String)
        )
        .void
      end
      def log_dependency_error(dependency:, error:, error_type:, error_detail: nil)
        if dependency.nil?
          depName = "no_dependency"
        else
          depName = dependency.name
        end

        if error_type == "unknown_error"
          Dependabot.logger.error "Error processing #{depName} (#{error.class.name})"
          Dependabot.logger.error error.message

          error.backtrace&.each { |line| Dependabot.logger.error line }
        else
          Dependabot.logger.info(
            "Handled error whilst updating #{depName}: #{error_type} #{error_detail}"
          )
        end
      end

      # This method handles errors where there is no dependency in the current
      # context.
      sig do
        params(
          error: StandardError,
          dependency_group: T.nilable(DependencyGroup)
        ).void
      end
      def handle_job_error(error:, dependency_group: nil)
        # If the error is fatal for the run, we should re-raise it rather than
        # pass it back to the service.
        raise error if RUN_HALTING_ERRORS.keys.any? { |err| error.is_a?(err) }

        error_details = error_details_for(error, dependency_group: dependency_group)
        service.record_update_job_error(
          error_type: error_details.fetch(:"error-type"),
          error_details: error_details[:"error-detail"]
        )
        # We don't set this flag in GHES because there older GHES version does not support reporting unknown errors.
        if Experiments.enabled?(:record_update_job_unknown_error) &&
           error_details.fetch(:"error-type") == "unknown_error"
          log_unknown_error_with_backtrace(error)
        end

        log_job_error(
          error: error,
          error_type: error_details.fetch(:"error-type"),
          error_detail: error_details.fetch(:"error-detail", nil)
        )
      end

      # Provides logging for errors that occur outside of a dependency context
      sig { params(error: StandardError, error_type: String, error_detail: T.untyped).void}
      def log_job_error(error:, error_type:, error_detail: nil)
        if error_type == "unknown_error"
          Dependabot.logger.error "Error processing job (#{error.class.name})"
          Dependabot.logger.error error.message
          error.backtrace&.each { |line| Dependabot.logger.error line }
        else
          Dependabot.logger.info(
            "Handled error whilst processing job: #{error_type} #{error_detail}"
          )
        end
      end

      private

      sig { returns(Service) }
      attr_reader :service
      sig { returns(Job) }
      attr_reader :job

      # This method accepts an error class and returns an appropriate `error_details` hash
      # to be reported to the backend service.
      #
      # For some specific errors, it also passes additional information to the
      # exception service to aid in debugging, the optional arguments provide
      # context to pass through in these cases.
      sig do
        params(
          error: StandardError,
          dependency: T.nilable(Dependency),
          dependency_group: T.nilable(DependencyGroup)
        )
        .returns(T::Hash[Symbol, T.untyped])
      end
      def error_details_for(error, dependency: nil, dependency_group: nil)
        error_details = Dependabot.updater_error_details(error)
        return error_details if error_details

        case error
        when Dependabot::SharedHelpers::HelperSubprocessFailed
          # If a helper subprocess has failed the error may include sensitive
          # info such as file contents or paths. This information is already
          # in the job logs, so we send a breadcrumb to Sentry to retrieve those
          # instead.
          msg = "Subprocess #{error.sentry_context[:fingerprint]} failed to run. Check the job logs for error messages"
          sanitized_error = SubprocessFailed.new(msg, sentry_context: error.sentry_context)
          sanitized_error.set_backtrace(error.backtrace)
          service.capture_exception(error: sanitized_error, job: job)
        else
          service.capture_exception(
            error: error,
            job: job,
            dependency: dependency,
            dependency_group: dependency_group
          )
        end

        { "error-type": "unknown_error" }
      end

      sig { params(error: StandardError).void }
      def log_unknown_error_with_backtrace(error)
        error_details = {
          ErrorAttributes::CLASS => error.class.to_s,
          ErrorAttributes::MESSAGE => error.message,
          ErrorAttributes::BACKTRACE => error.backtrace&.join("\n"),
          ErrorAttributes::FINGERPRINT => error.respond_to?(:sentry_context) ?
            T.unsafe(error).sentry_context[:fingerprint] : nil,
          ErrorAttributes::PACKAGE_MANAGER => job.package_manager,
          ErrorAttributes::JOB_ID => job.id,
          ErrorAttributes::DEPENDENCIES => job.dependencies,
          ErrorAttributes::DEPENDENCY_GROUPS => job.dependency_groups
        }.compact

        service.increment_metric("updater.update_job_unknown_error", tags: {
          package_manager: job.package_manager,
          class_name: error.class.name
        })
        service.record_update_job_unknown_error(error_type: "unknown_error", error_details: error_details)
      end
    end
  end
end
