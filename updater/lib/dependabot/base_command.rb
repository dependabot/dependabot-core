# frozen_string_literal: true

require "raven"
require "dependabot/api_client"
require "dependabot/service"
require "dependabot/logger"
require "dependabot/logger/formats"
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
      Dependabot.logger.formatter = Dependabot::Logger::BasicFormatter.new
      Dependabot.logger.info(service.summary) unless service.noop?
      raise Dependabot::RunFailure if Dependabot::Environment.github_actions? && service.failure?
    end

    def handle_exception(err)
      Dependabot.logger.error(err.message)
      err.backtrace.each { |line| Dependabot.logger.error(line) }

      Raven.capture_exception(err, raven_context)

      service.record_update_job_error(error_type: "unknown_error", error_details: { message: err.message })
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

    private

    def raven_context
      context = { tags: {}, extra: { update_job_id: job_id } }
      context[:tags][:package_manager] = job.package_manager if job
      context
    end
  end
end
