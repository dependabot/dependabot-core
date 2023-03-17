# frozen_string_literal: true

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

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/MethodLength
      def handle_dependabot_error(error:, dependency:)
        # If the error is fatal for the run, we should re-raise it rather than
        # pass it back to the service.
        raise error if RUN_HALTING_ERRORS.keys.any? { |err| error.is_a?(err) }

        error_details =
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
              dependency: dependency
            )
            { "error-type": "unknown_error" }
          end

        service.record_update_job_error(
          error_type: error_details.fetch(:"error-type"),
          error_details: error_details[:"error-detail"],
          dependency: dependency
        )

        log_error(
          dependency: dependency,
          error: error,
          error_type: error_details.fetch(:"error-type"),
          error_detail: error_details.fetch(:"error-detail", nil)
        )
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize

      # rubocop:disable Metrics/MethodLength
      def handle_parser_error(error)
        # This happens if the repo gets removed after a job gets kicked off.
        # The service will handle the removal without any prompt from the updater,
        # so no need to add an error to the errors array
        return if error.is_a? Dependabot::RepoNotFound

        error_details =
          case error
          when Dependabot::DependencyFileNotEvaluatable
            {
              "error-type": "dependency_file_not_evaluatable",
              "error-detail": { message: error.message }
            }
          when Dependabot::DependencyFileNotResolvable
            {
              "error-type": "dependency_file_not_resolvable",
              "error-detail": { message: error.message }
            }
          when Dependabot::BranchNotFound
            {
              "error-type": "branch_not_found",
              "error-detail": { "branch-name": error.branch_name }
            }
          when Dependabot::DependencyFileNotParseable
            {
              "error-type": "dependency_file_not_parseable",
              "error-detail": {
                message: error.message,
                "file-path": error.file_path
              }
            }
          when Dependabot::DependencyFileNotFound
            {
              "error-type": "dependency_file_not_found",
              "error-detail": { "file-path": error.file_path }
            }
          when Dependabot::PathDependenciesNotReachable
            {
              "error-type": "path_dependencies_not_reachable",
              "error-detail": { dependencies: error.dependencies }
            }
          when Dependabot::PrivateSourceAuthenticationFailure
            {
              "error-type": "private_source_authentication_failure",
              "error-detail": { source: error.source }
            }
          when Dependabot::GitDependenciesNotReachable
            {
              "error-type": "git_dependencies_not_reachable",
              "error-detail": { "dependency-urls": error.dependency_urls }
            }
          when Dependabot::NotImplemented
            {
              "error-type": "not_implemented",
              "error-detail": {
                message: error.message
              }
            }
          when Octokit::ServerError
            # If we get a 500 from GitHub there's very little we can do about it,
            # and responsibility for fixing it is on them, not us. As a result we
            # quietly log these as errors
            { "error-type": "unknown_error" }
          else
            raise if RUN_HALTING_ERRORS.keys.any? { |e| error.is_a?(e) }

            Dependabot.logger.error error.message
            error.backtrace.each { |line| Dependabot.logger.error line }

            service.capture_exception(error: error, job: job)
            { "error-type": "unknown_error" }
          end

        service.record_update_job_error(
          error_type: error_details.fetch(:"error-type"),
          error_details: error_details[:"error-detail"]
        )
      end
      # rubocop:enable Metrics/MethodLength

      def log_error(dependency:, error:, error_type:, error_detail: nil)
        if error_type == "unknown_error"
          Dependabot.logger.error "Error processing #{dependency.name} (#{error.class.name})"
          Dependabot.logger.error error.message
          error.backtrace.each { |line| Dependabot.logger.error line }
        else
          Dependabot.logger.info(
            "Handled error whilst updating #{dependency.name}: #{error_type} #{error_detail}"
          )
        end
      end

      private

      attr_reader :service, :job
    end
  end
end
