# typed: strict
# frozen_string_literal: true

require "base64"
require "json"
require "dependabot/base_command"
require "dependabot/dependency_snapshot"
require "dependabot/errors"
require "dependabot/opentelemetry"
require "dependabot/updater"
require "github_api/dependency_submission"

module Dependabot
  class UpdateGraphCommand < BaseCommand
    extend T::Sig

    # TODO(brrygrdn): Change label to update_graph_error?
    #
    # It feels odd to return update_files_error, but Dependabot's backend service does a lot of categorisation
    # based on this label.
    #
    # We need to ensure that the service handles a new update_graph_error appropriately before we change this,
    # but this is something we can address later.
    ERROR_TYPE_LABEL = "update_files_error"

    sig { override.void }
    def perform_job
      ::Dependabot::OpenTelemetry.tracer.in_span("update_graph", kind: :internal) do |span|
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id.to_s)

        begin
          # We expect the FileFetcherCommand to have been executed beforehand to place
          # encoded files and commit information in the environment, so let's retrieve
          # them, decode and parse them into an object that knows the current state
          # of the project's dependencies.
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

        submission = build_submission(dependency_snapshot)
        Dependabot.logger.info("Dependency submission payload:\n#{JSON.pretty_generate(submission.payload)}")

        # For now, we require the experiment to actually submit data as this alters repository dependency state
        # so we should be very intentional in the event this is called by accident.
        if Dependabot::Experiments.enabled?(:enable_dependency_submission_poc)
          service.create_dependency_submission(dependency_submission: submission)
        end

        service.mark_job_as_processed(dependency_snapshot.base_commit_sha)
      end
    end

    sig { override.returns(Dependabot::Job) }
    def job
      @job ||= T.let(
        Job.new_update_job(
          job_id: job_id,
          job_definition: Environment.job_definition,
          repo_contents_path: Environment.repo_contents_path
        ),
        T.nilable(Dependabot::Job)
      )
    end

    sig { override.returns(T.nilable(String)) }
    def base_commit_sha
      Environment.job_definition["base_commit_sha"]
    end

    private

    sig { params(dependency_snapshot: Dependabot::DependencySnapshot).returns(GithubApi::DependencySubmission) }
    def build_submission(dependency_snapshot)
      GithubApi::DependencySubmission.new(
        job_id: job.id.to_s,
        branch: job.source.branch || "main",
        sha: dependency_snapshot.base_commit_sha,
        ecosystem: T.must(dependency_snapshot.ecosystem),
        dependency_files: dependency_snapshot.dependency_files,
        dependencies: dependency_snapshot.dependencies
      )
    end

    sig { params(error: StandardError).void }
    def handle_parser_error(error) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity
      # This happens if the repo gets removed after a job gets kicked off.
      # The service will handle the removal without any prompt from the updater,
      # so no need to add an error to the errors array
      return if error.is_a? Dependabot::RepoNotFound

      error_details = Dependabot.parser_error_details(error)

      error_details ||=
        # Check if the error is a known "run halting" state we should handle
        if (error_type = Updater::ErrorHandler::RUN_HALTING_ERRORS[error.class])
          { "error-type": error_type }
        elsif error.is_a?(ToolVersionNotSupported)
          Dependabot.logger.error(error.message)
          {
            "error-type": "tool_version_not_supported",
            "error-detail": {
              "tool-name": error.tool_name,
              "detected-version": error.detected_version,
              "supported-versions": error.supported_versions
            }
          }
        else
          # If it isn't, then log all the details and let the application error
          # tracker know about it
          Dependabot.logger.error error.message
          error.backtrace&.each { |line| Dependabot.logger.error line }
          unknown_error_details = {
            ErrorAttributes::CLASS => error.class.to_s,
            ErrorAttributes::MESSAGE => error.message,
            ErrorAttributes::BACKTRACE => error.backtrace&.join("\n"),
            ErrorAttributes::FINGERPRINT => (if error.respond_to?(:sentry_context)
                                               T.unsafe(error).sentry_context[:fingerprint]
                                             end),
            ErrorAttributes::PACKAGE_MANAGER => job.package_manager,
            ErrorAttributes::JOB_ID => job.id,
            ErrorAttributes::DEPENDENCIES => job.dependencies,
            ErrorAttributes::DEPENDENCY_GROUPS => job.dependency_groups
          }.compact

          service.capture_exception(error: error, job: job)

          # Set an unknown error type as update_files_error to be added to the job
          {
            "error-type": ERROR_TYPE_LABEL,
            "error-detail": unknown_error_details
          }
        end

      service.record_update_job_error(
        error_type: error_details.fetch(:"error-type"),
        error_details: error_details[:"error-detail"]
      )
      # We don't set this flag in GHES because there older GHES version does not support reporting unknown errors.
      return unless Experiments.enabled?(:record_update_job_unknown_error)
      return unless error_details.fetch(:"error-type") == ERROR_TYPE_LABEL

      service.record_update_job_unknown_error(
        error_type: error_details.fetch(:"error-type"),
        error_details: error_details[:"error-detail"]
      )
    end
  end
end
