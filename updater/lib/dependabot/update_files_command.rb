# frozen_string_literal: true

require "base64"
require "dependabot/base_command"
require "dependabot/updater"

module Dependabot
  class UpdateFilesCommand < BaseCommand
    def perform_job
      Dependabot::Updater.new(
        service: service,
        job_id: job_id,
        job: job,
        dependency_files: dependency_files,
        repo_contents_path: repo_contents_path,
        base_commit_sha: base_commit_sha
      ).run

      service.mark_job_as_processed(base_commit_sha)
    end

    def job
      @job ||= Job.new_update_job(job_id, Environment.job_definition)
    end

    def dependency_files
      @dependency_files ||=
        Environment.job_definition["base64_dependency_files"].map do |a|
          file = Dependabot::DependencyFile.new(**a.transform_keys(&:to_sym))
          file.content = Base64.decode64(file.content).force_encoding("utf-8") unless file.binary? && !file.deleted?
          file
        end
    end

    def repo_contents_path
      return nil unless job.clone?

      Environment.repo_contents_path
    end

    def base_commit_sha
      Environment.job_definition["base_commit_sha"]
    end
  end
end
