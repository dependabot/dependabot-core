# typed: true
# frozen_string_literal: true

require "dependabot/api_client"
require "dependabot/service"
require "dependabot/logger"
require "dependabot/logger/formats"
require "dependabot/environment"

module Dependabot
  class RunFailure < StandardError; end

  class BaseCommand
    # Implement in subclass
    def perform_job
      raise NotImplementedError
    end

    # Implement in subclass
    def job
      raise NotImplementedError
    end

    # Implement in subclass
    def base_commit_sha
      raise NotImplementedError
    end

    # TODO: Avoid rescuing StandardError at this point in the code
    #
    # This means that exceptions in tests can occasionally be swallowed
    # and we must rely on reading RSpec output to detect certain problems.
    def run
      Dependabot.logger.formatter = Dependabot::Logger::JobFormatter.new(job_id)
      Dependabot.logger.info("Starting job processing")
      perform_job
      Dependabot.logger.info("Finished job processing")
    rescue StandardError => e
      handle_exception(e)
      service.mark_job_as_processed(base_commit_sha)
    ensure
      # Ensure that we shut down the open telemetry exporter.
      ::Dependabot::OpenTelemetry.shutdown
      Dependabot.logger.formatter = Dependabot::Logger::BasicFormatter.new
      Dependabot.logger.info(service.summary) unless service.noop?
      raise Dependabot::RunFailure if Dependabot::Environment.github_actions? && service.failure?
    end

    def handle_exception(err)
      Dependabot.logger.error(err.message)
      err.backtrace.each { |line| Dependabot.logger.error(line) }
      service.capture_exception(error: err, job: job)
      service.record_update_job_error(error_type: "unknown_error", error_details: { message: err.message })
      # We don't set this flag in GHES because there older GHES version does not support reporting unknown errors.
      handle_unknown_error(err) if Experiments.enabled?(:record_update_job_unknown_error)
    end

    def handle_unknown_error(err)
      error_details = {
        "error-class" => err.class.to_s,
        "error-message" => err.message,
        "error-backtrace" => err.backtrace.join("\n"),
        "package-manager" => job.package_manager,
        "job-id" => job.id,
        "job-dependencies" => job.dependencies,
        "job-dependency-group" => job.dependency_groups
      }.compact
      service.record_update_job_unknown_error(error_type: "updater_error", error_details: error_details)
      service.increment_metric("updater.update_job_unknown_error", tags: {
        package_manager: job.package_manager,
        class_name: err.class.name
      })
    end

    def job_id
      Environment.job_id
    end

    def api_client
      @api_client ||= Dependabot::ApiClient.new(
        Environment.api_url,
        job_id,
        Environment.job_token
      )
    end

    def service
      @service ||= Dependabot::Service.new(client: api_client)
    end
  end
end
