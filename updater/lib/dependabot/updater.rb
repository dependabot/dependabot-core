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

# Ecosystems
require "dependabot/python"
require "dependabot/terraform"
require "dependabot/elm"
require "dependabot/docker"
require "dependabot/git_submodules"
require "dependabot/github_actions"
require "dependabot/composer"
require "dependabot/nuget"
require "dependabot/gradle"
require "dependabot/maven"
require "dependabot/hex"
require "dependabot/cargo"
require "dependabot/go_modules"
require "dependabot/npm_and_yarn"
require "dependabot/bundler"
require "dependabot/pub"
require "dependabot/swift"

# Updater components
require "dependabot/updater/error_handler"
require "dependabot/updater/operations"
require "dependabot/updater/security_update_helpers"

require "wildcard_matcher"

module Dependabot
  class Updater
    # To do work, this class needs three arguments:
    # - The Dependabot::Service to send events and outcomes to
    # - The Dependabot::Job that describes the work to be done
    # - The Dependabot::DependencySnapshot which encapsulates the starting state of the project
    def initialize(service:, job:, dependency_snapshot:)
      @service = service
      @job = job
      @dependency_snapshot = dependency_snapshot
      @error_handler = ErrorHandler.new(service: service, job: job)
    end

    def run
      return unless job
      raise Dependabot::NotImplemented unless (operation_class = Operations.class_for(job: job))

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
        service.capture_exception(error: error, job: job)
        return
      end

      # OOM errors are special cased so that we stop the update run early
      service.record_update_job_error(
        error_type: ErrorHandler::RUN_HALTING_ERRORS.fetch(e.class),
        error_details: nil
      )
    end

    private

    attr_reader :service, :job, :dependency_snapshot, :error_handler
  end
end
