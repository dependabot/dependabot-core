# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

# Dependabot components
require "dependabot/environment"
require "dependabot/experiments"
require "dependabot/dependency_graphers"
require "dependabot/logger"

# Updater components
require "dependabot/updater/error_handler"
require "github_api/dependency_submission"

# This class is responsible for iterating the list of directories within a repository that the job specifies
# and submitting a snapshot of each to the GitHub Dependency Submission API.
module Dependabot
  class UpdateGraphProcessor
    extend T::Sig

    # To do work, this class needs three arguments:
    # - The Dependabot::Service to send events and outcomes to
    # - The Dependabot::Job that describes the work to be done
    # - The Dependabot::DependencyFile list retrieved by the file fetcher
    # - The base_commit_sha being processed
    sig do
      params(
        service: Dependabot::Service,
        job: Dependabot::Job,
        base_commit_sha: String,
        dependency_files: T::Array[Dependabot::DependencyFile]
      ).void
    end
    def initialize(service:, job:, base_commit_sha:, dependency_files:)
      @service = service
      @job = job
      @base_commit_sha = base_commit_sha
      @dependency_files = dependency_files

      @error_handler = Dependabot::Updater::ErrorHandler.new(service: service, job: job)
    end

    sig { void }
    def run
      parser = Dependabot::FileParsers.for_package_manager(job.package_manager).new(
        dependency_files: dependency_files,
        repo_contents_path: job.repo_contents_path,
        source: job.source,
        credentials: job.credentials,
        reject_external_code: job.reject_external_code?,
        options: job.experiments
      )

      grapher = Dependabot::DependencyGraphers.for_package_manager(job.package_manager).new(
        dependency_files: dependency_files,
        dependencies: parser.parse
      )

      # TODO(brrygdn): This should be called once per directory in future
      submission = GithubApi::DependencySubmission.new(
        job_id: job.id.to_s,
        # TODO(brrygrdn): We should not tolerate this being null for graph jobs
        branch: job.source.branch || "main",
        sha: base_commit_sha,
        package_manager: job.package_manager,
        manifest_file: grapher.relevant_dependency_file,
        resolved_dependencies: grapher.resolved_dependencies
      )

      Dependabot.logger.info("Dependency submission payload:\n#{JSON.pretty_generate(submission.payload)}")
      service.create_dependency_submission(dependency_submission: submission)
    end

    private

    sig { returns(Dependabot::Service) }
    attr_reader :service

    sig { returns(Dependabot::Job) }
    attr_reader :job

    sig { returns(String) }
    attr_reader :base_commit_sha

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    attr_reader :dependency_files

    sig { returns(Dependabot::Updater::ErrorHandler) }
    attr_reader :error_handler
  end
end
