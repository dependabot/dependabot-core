# typed: strong
# frozen_string_literal: true

# Dependabot components
require "dependabot/dependency_change"
require "dependabot/dependency_change_builder"
require "dependabot/environment"
require "dependabot/experiments"
require "dependabot/file_fetchers"
require "dependabot/logger"
require "dependabot/security_advisory"
require "dependabot/update_checkers"

# Updater components
require "dependabot/updater/error_handler"
require "dependabot/updater/operations"
require "dependabot/updater/security_update_helpers"

require "sorbet-runtime"
require "wildcard_matcher"

module Dependabot
  class Updater
    extend T::Sig
    # To do work, this class needs three arguments:
    # - The Dependabot::Service to send events and outcomes to
    # - The Dependabot::Job that describes the work to be done
    # - The Dependabot::DependencySnapshot which encapsulates the starting state of the project
    sig { params(service: Service, job: Job, dependency_snapshot: DependencySnapshot).void }
    def initialize(service:, job:, dependency_snapshot:)
      @service = service
      @job = job
      @dependency_snapshot = dependency_snapshot
      @error_handler = T.let(ErrorHandler.new(service: service, job: job), ErrorHandler)
    end

    sig { void }
    def run
      unless (operation_class = Operations.class_for(job: @job))
        raise Dependabot::NotImplemented
      end

      Dependabot.logger.debug("Performing job with #{operation_class}")
      service.increment_metric("updater.started", tags: { operation: operation_class.tag_name })
      operation_class.new(
        service: service,
        job: job,
        dependency_snapshot: dependency_snapshot,
        error_handler: error_handler
      ).perform
    rescue *ErrorHandler::RUN_HALTING_ERRORS.keys => e
      # TODO: Drop this into Security-specific operations
      if e.is_a?(Dependabot::AllVersionsIgnored) && !job.security_updates_only?
        error = StandardError.new(
          "Dependabot::AllVersionsIgnored was unexpectedly raised for a non-security update job"
        )
        error.set_backtrace(e.backtrace)
        @service.capture_exception(error: error, job: job)
        return
      end

      # OOM errors are special cased so that we stop the update run early
      service.record_update_job_error(
        error_type: ErrorHandler::RUN_HALTING_ERRORS.fetch(e.class),
        error_details: nil
      )
    end

    private

    sig { returns(Service) }
    attr_reader :service

    sig { returns(Job) }
    attr_reader :job

    sig { returns(DependencySnapshot) }
    attr_reader :dependency_snapshot

    sig { returns(ErrorHandler) }
    attr_reader :error_handler
  end
end
