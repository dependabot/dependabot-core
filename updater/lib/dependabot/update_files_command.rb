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
      attrs =
        Environment.job_definition["job"].
        transform_keys { |key| key.tr("-", "_") }.
        transform_keys(&:to_sym).
        tap { |h| h[:credentials] = h.delete(:credentials_metadata) || [] }.
        slice(
          :dependencies, :package_manager, :ignore_conditions,
          :existing_pull_requests, :source, :lockfile_only, :allowed_updates,
          :update_subdependencies, :updating_a_pull_request, :credentials,
          :requirements_update_strategy, :security_advisories,
          :vendor_dependencies, :experiments, :reject_external_code,
          :commit_message_options, :security_updates_only
        )

      @job ||= Job.new(attrs)
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
