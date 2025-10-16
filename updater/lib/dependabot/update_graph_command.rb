# typed: strict
# frozen_string_literal: true

require "json"
require "dependabot/base_command"
require "dependabot/fetched_files"
require "dependabot/dependency_snapshot"
require "dependabot/errors"
require "dependabot/opentelemetry"
require "dependabot/update_graph_processor"
require "github_api/dependency_submission"

module Dependabot
  class UpdateGraphCommand < BaseCommand
    extend T::Sig

    ERROR_TYPE_LABEL = "update_graph_error"

    sig { params(fetched_files: Dependabot::FetchedFiles).void }
    def initialize(fetched_files)
      @fetched_files = T.let(fetched_files, Dependabot::FetchedFiles)
    end

    sig { override.void }
    def perform_job
      ::Dependabot::OpenTelemetry.tracer.in_span("update_graph", kind: :internal) do |span|
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id.to_s)

        Dependabot::UpdateGraphProcessor.new(
          service: service,
          job: job,
          base_commit_sha: @fetched_files.base_commit_sha,
          dependency_files: @fetched_files.dependency_files
        ).run
      rescue StandardError => e
        handle_error(e)
      ensure
        service.mark_job_as_processed(base_commit_sha)
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
      @fetched_files.base_commit_sha
    end

    private

    sig { params(error: StandardError).void }
    def handle_error(error) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity
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
