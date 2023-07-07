# typed: false
# frozen_string_literal: true

require "dependabot/updater/errors"

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
      # These are errors that halt the update run and are handled in the main
      # backend. They do *not* raise a sentry.
      RUN_HALTING_ERRORS = {
        Dependabot::OutOfDisk => "out_of_disk",
        Dependabot::OutOfMemory => "out_of_memory",
        Dependabot::AllVersionsIgnored => "all_versions_ignored",
        Dependabot::UnexpectedExternalCode => "unexpected_external_code",
        Errno::ENOSPC => "out_of_disk",
        Octokit::Unauthorized => "octokit_unauthorized"
      }.freeze

      def initialize(service:, job:)
        @service = service
        @job = job
      end

      # This method handles errors where there is a dependency in the current
      # context. This should be used by preference where possible.
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

        log_dependency_error(
          dependency: dependency,
          error: error,
          error_type: error_details.fetch(:"error-type"),
          error_detail: error_details.fetch(:"error-detail", nil)
        )
      end

      # Provides logging for errors that occur when processing a dependency
      def log_dependency_error(dependency:, error:, error_type:, error_detail: nil)
        if error_type == "unknown_error"
          Dependabot.logger.error "Error processing #{dependency.name} (#{error.class.name})"
          log_unknown_error_with_backtrace(error)
        else
          Dependabot.logger.info(
            "Handled error whilst updating #{dependency.name}: #{error_type} #{error_detail}"
          )
        end
      end

      # This method handles errors where there is no dependency in the current
      # context.
      def handle_job_error(error:, dependency_group: nil)
        # If the error is fatal for the run, we should re-raise it rather than
        # pass it back to the service.
        raise error if RUN_HALTING_ERRORS.keys.any? { |err| error.is_a?(err) }

        error_details = error_details_for(error, dependency_group: dependency_group)
        service.record_update_job_error(
          error_type: error_details.fetch(:"error-type"),
          error_details: error_details[:"error-detail"]
        )
        log_job_error(
          error: error,
          error_type: error_details.fetch(:"error-type"),
          error_detail: error_details.fetch(:"error-detail", nil)
        )
      end

      # Provides logging for errors that occur outside of a dependency context
      def log_job_error(error:, error_type:, error_detail: nil)
        if error_type == "unknown_error"
          Dependabot.logger.error "Error processing job (#{error.class.name})"
          log_unknown_error_with_backtrace(error)
        else
          Dependabot.logger.info(
            "Handled error whilst processing job: #{error_type} #{error_detail}"
          )
        end
      end

      private

      attr_reader :service, :job

      # This method accepts an error class and returns an appropriate `error_details` hash
      # to be reported to the backend service.
      #
      # For some specific errors, it also passes additional information to the
      # exception service to aid in debugging, the optional arguments provide
      # context to pass through in these cases.
      def error_details_for(error, dependency: nil, dependency_group: nil) # rubocop:disable Metrics/MethodLength
        case error
        when Dependabot::DependencyFileNotResolvable
          {
            "error-type": "dependency_file_not_resolvable",
            "error-detail": { message: error.message }
          }
        when Dependabot::DependencyFileNotEvaluatable
          {
            "error-type": "dependency_file_not_evaluatable",
            "error-detail": { message: error.message }
          }
        when Dependabot::GitDependenciesNotReachable
          {
            "error-type": "git_dependencies_not_reachable",
            "error-detail": { "dependency-urls": error.dependency_urls }
          }
        when Dependabot::GitDependencyReferenceNotFound
          {
            "error-type": "git_dependency_reference_not_found",
            "error-detail": { dependency: error.dependency }
          }
        when Dependabot::PrivateSourceAuthenticationFailure
          {
            "error-type": "private_source_authentication_failure",
            "error-detail": { source: error.source }
          }
        when Dependabot::PrivateSourceTimedOut
          {
            "error-type": "private_source_timed_out",
            "error-detail": { source: error.source }
          }
        when Dependabot::PrivateSourceCertificateFailure
          {
            "error-type": "private_source_certificate_failure",
            "error-detail": { source: error.source }
          }
        when Dependabot::MissingEnvironmentVariable
          {
            "error-type": "missing_environment_variable",
            "error-detail": {
              "environment-variable": error.environment_variable
            }
          }
        when Dependabot::GoModulePathMismatch
          {
            "error-type": "go_module_path_mismatch",
            "error-detail": {
              "declared-path": error.declared_path,
              "discovered-path": error.discovered_path,
              "go-mod": error.go_mod
            }
          }
        when Dependabot::NotImplemented
          {
            "error-type": "not_implemented",
            "error-detail": {
              message: error.message
            }
          }
        when Dependabot::SharedHelpers::HelperSubprocessFailed
          # If a helper subprocess has failed the error may include sensitive
          # info such as file contents or paths. This information is already
          # in the job logs, so we send a breadcrumb to Sentry to retrieve those
          # instead.
          msg = "Subprocess #{error.raven_context[:fingerprint]} failed to run. Check the job logs for error messages"
          sanitized_error = SubprocessFailed.new(msg, raven_context: error.raven_context)
          sanitized_error.set_backtrace(error.backtrace)
          service.capture_exception(error: sanitized_error, job: job)

          { "error-type": "unknown_error" }
        when *Octokit::RATE_LIMITED_ERRORS
          # If we get a rate-limited error we let dependabot-api handle the
          # retry by re-enqueing the update job after the reset
          {
            "error-type": "octokit_rate_limited",
            "error-detail": {
              "rate-limit-reset": error.response_headers["X-RateLimit-Reset"]
            }
          }
        else
          service.capture_exception(
            error: error,
            job: job,
            dependency: dependency,
            dependency_group: dependency_group
          )
          { "error-type": "unknown_error" }
        end
      end

      def log_unknown_error_with_backtrace(error)
        Dependabot.logger.error error.message
        error.backtrace.each { |line| Dependabot.logger.error line }
        service.increment_metric("updater.unknown_error", tags: {
          package_manager: job.package_manager,
          class_name: error.class.name,
        })
      end
    end
  end
end
