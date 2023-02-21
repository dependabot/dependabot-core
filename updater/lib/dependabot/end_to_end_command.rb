# frozen_string_literal: true

require "dependabot/base_command"
require "dependabot/updater"

module Dependabot
  class EndToEndCommand < BaseCommand
    def perform_job
      begin
        base_commit_sha
        dependency_files
      rescue StandardError => e
        logger_error("Error during file fetching; aborting")
        handle_file_fetcher_error(e)
        service.mark_job_as_processed(job_id, base_commit_sha)
        return
      end

      Dependabot::Updater.new(
        service: service,
        job_id: job_id,
        job: job,
        dependency_files: dependency_files,
        base_commit_sha: base_commit_sha,
        repo_contents_path: Environment.repo_contents_path
      ).run

      service.mark_job_as_processed(job_id, base_commit_sha)
    end

    def job
      @job ||= service.get_job(job_id)
    end

    private

    def dependency_files
      file_fetcher.files
    rescue Octokit::BadGateway
      @file_fetcher_retries ||= 0
      @file_fetcher_retries += 1
      @file_fetcher_retries <= 2 ? retry : raise
    end

    def base_commit_sha
      @base_commit_sha ||= file_fetcher.commit || "unknown"
    rescue StandardError
      # If an error occurs, set the commit SHA instance variable (so that we
      # don't raise when recording the error later) and re-raise
      @base_commit_sha = "unknown"
      raise
    end

    def file_fetcher
      @file_fetcher ||=
        Dependabot::FileFetchers.for_package_manager(job.package_manager).new(
          source: job.source,
          credentials: job.credentials
        )
    end

    # rubocop:disable Metrics/MethodLength
    def handle_file_fetcher_error(error)
      error_details =
        case error
        when Dependabot::BranchNotFound
          {
            "error-type": "branch_not_found",
            "error-detail": { "branch-name": error.branch_name }
          }
        when Dependabot::RepoNotFound
          # This happens if the repo gets removed after a job gets kicked off.
          # The main backend will handle it without any prompt from the updater,
          # so no need to add an error to the errors array
          nil
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
        when Octokit::ServerError
          # If we get a 500 from GitHub there's very little we can do about it,
          # and responsibility for fixing it is on them, not us. As a result we
          # quietly log these as errors
          { "error-type": "unknown_error" }
        else
          logger_error error.message
          error.backtrace.each { |line| logger_error line }
          Raven.capture_exception(error, raven_context)

          { "error-type": "unknown_error" }
        end

      record_error(error_details) if error_details
    end

    # rubocop:enable Metrics/MethodLength
    def record_error(error_details)
      service.record_update_job_error(
        job_id,
        error_type: error_details.fetch(:"error-type"),
        error_details: error_details[:"error-detail"]
      )
    end
  end
end
