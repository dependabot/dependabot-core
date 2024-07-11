# typed: strict
# frozen_string_literal: true

require "dependabot/api_client"
require "dependabot/errors"
require "dependabot/service"
require "dependabot/logger"
require "dependabot/logger/formats"
require "dependabot/environment"

require "sorbet-runtime"

module Dependabot
  class RunFailure < StandardError; end

  class BaseCommand
    extend T::Sig

    # Implement in subclass
    sig { overridable.void }
    def perform_job
      raise NotImplementedError
    end

    # Implement in subclass
    sig { overridable.returns(Job) }
    def job
      raise NotImplementedError
    end

    # Implement in subclass
    sig { overridable.returns(String) }
    def base_commit_sha
      raise NotImplementedError
    end

    # TODO: Avoid rescuing StandardError at this point in the code
    #
    # This means that exceptions in tests can occasionally be swallowed
    # and we must rely on reading RSpec output to detect certain problems.
    sig { void }
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

    sig { params(err: StandardError).void }
    def handle_exception(err)
      Dependabot.logger.error(err.message)
      err.backtrace&.each { |line| Dependabot.logger.error(line) }
      service.capture_exception(error: err, job: job)
      service.record_update_job_error(error_type: "unknown_error", error_details: { message: err.message })
      # We don't set this flag in GHES because there older GHES version does not support reporting unknown errors.
      handle_unknown_error(err) if Experiments.enabled?(:record_update_job_unknown_error)
    end

    sig { params(err: StandardError).void }
    def handle_unknown_error(err)
      error_details = {
        ErrorAttributes::CLASS => err.class.to_s,
        ErrorAttributes::MESSAGE => err.message,
        ErrorAttributes::BACKTRACE => err.backtrace&.join("\n"),
        ErrorAttributes::FINGERPRINT => err.respond_to?(:sentry_context) ?
          T.unsafe(err).sentry_context[:fingerprint] : nil,
        ErrorAttributes::PACKAGE_MANAGER => job.package_manager,
        ErrorAttributes::JOB_ID => job.id,
        ErrorAttributes::DEPENDENCIES => job.dependencies,
        ErrorAttributes::DEPENDENCY_GROUPS => job.dependency_groups
      }.compact
      service.record_update_job_unknown_error(error_type: "updater_error", error_details: error_details)
      service.increment_metric("updater.update_job_unknown_error", tags: {
        package_manager: job.package_manager,
        class_name: err.class.name
      })
    end

    sig { returns(String) }
    def job_id
      Environment.job_id
    end

    sig { returns(ApiClient) }
    def api_client
      @api_client ||= T.let(
        Dependabot::ApiClient.new(
          Environment.api_url,
          job_id,
          Environment.job_token
        ), T.nilable(ApiClient)
      )
    end

    sig { returns(Service) }
    def service
      @service ||= T.let(Dependabot::Service.new(client: api_client), T.nilable(Service))
    end
  end
end
