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
      # and decode them into an object.

      # TODO: Parse the dependency files when instantiated
      #
      # We can pull the error handling for parser exceptions up into this class to
      # completely remove the concern from Dependabot::Updater.
      #
      # This should happen separately to introducing the class as a shim.
      #
      # See: updater/lib/dependabot/dependency_snapshot.rb:52
      dependency_snapshot = Dependabot::DependencySnapshot.create_from_job_definition(
        job: job,
        job_definition: Environment.job_definition
      )

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
  end
end
