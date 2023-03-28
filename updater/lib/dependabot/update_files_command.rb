# frozen_string_literal: true

require "base64"
require "dependabot/base_command"
require "dependabot/dependency_snapshot"
require "dependabot/updater"

module Dependabot
  class UpdateFilesCommand < BaseCommand
    def perform_job
      # We expect the FileFetcherCommand to have been executed beforehand to place
      # encoded files and commit information in the environment, so let's retrieve
      # them, decode and parse them into an object that knows the current state
      # of the project's dependencies.
      begin
        dependency_snapshot = Dependabot::DependencySnapshot.create_from_job_definition(
          job: job,
          job_definition: Environment.job_definition
        )
      rescue StandardError => e
        handle_parser_error(e)
        # If dependency file parsing has failed, there's nothing more we can do,
        # so let's mark the job as processed and stop.
        return service.mark_job_as_processed(Environment.job_definition["base_commit_sha"])
      end

      # TODO: Pull fatal error handling handling up into this class
      #
      # As above, we can remove the responsibility for handling fatal/job halting
      # errors from Dependabot::Updater entirely.
      Dependabot::Updater.new(
        service: service,
        job: job,
        dependency_snapshot: dependency_snapshot
      ).run

      # Finally, mark the job as processed. The Dependabot::Updater may have
      # reported errors to the service, but we always consider the job as
      # successfully processed unless it actually raises.
      service.mark_job_as_processed(dependency_snapshot.base_commit_sha)
    end

    private

    def job
      @job ||= Job.new_update_job(
        job_id: job_id,
        job_definition: Environment.job_definition,
        repo_contents_path: Environment.repo_contents_path
      )
    end

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
          # Check if the error is a known "run halting" state we should handle
          if (error_type = Updater::ErrorHandler::RUN_HALTING_ERRORS[error.class])
            { "error-type": error_type }
          else
            # If it isn't, then log all the details and let the application error
            # tracker know about it
            Dependabot.logger.error error.message
            error.backtrace.each { |line| Dependabot.logger.error line }

            service.capture_exception(error: error, job: job)

            # Set an unknown error type to be added to the job
            { "error-type": "unknown_error" }
          end
        end

      service.record_update_job_error(
        error_type: error_details.fetch(:"error-type"),
        error_details: error_details[:"error-detail"]
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
