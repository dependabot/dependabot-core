# typed: strict
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

      @error_handler = T.let(
        Dependabot::Updater::ErrorHandler.new(service: service, job: job),
        Dependabot::Updater::ErrorHandler
      )
    end

    sig { void }
    def run
      raise Dependabot::DependabotError, "job.source.directories is nil" if job.source.directories.nil?
      raise Dependabot::DependabotError, "job.source.directories is empty" unless job.source.directories&.any?

      T.must(job.source.directories).each do |directory|
        directory_source = create_source_for(directory)
        directory_dependency_files = dependency_files_for(directory)

        submission = create_submission(directory_source, directory_dependency_files)

        Dependabot.logger.info("Dependency submission payload:\n#{JSON.pretty_generate(submission.payload)}")
        service.create_dependency_submission(dependency_submission: submission)
      end
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

    sig { params(directory: String).returns(Dependabot::Source) }
    def create_source_for(directory)
      job.source.dup.tap do |s|
        s.directory = directory
      end
    end

    sig { params(directory: String).returns(T::Array[Dependabot::DependencyFile]) }
    def dependency_files_for(directory)
      dependency_files.select { |f| f.directory == directory }
    end

    sig do
      params(
        source: Dependabot::Source,
        files: T::Array[Dependabot::DependencyFile]
      ).returns(GithubApi::DependencySubmission)
    end
    def create_submission(source, files)
      # return an empty submission if there are no files
      if files.empty?
        return GithubApi::DependencySubmission.new(
          job_id: job.id.to_s,
          # FIXME(brrygrdn): We should obtain the ref from git -or- inject it via the backend service
          branch: source.branch || "main",
          sha: base_commit_sha,
          package_manager: job.package_manager,
          manifest_file: DependencyFile.new(name: "", content: "", directory: T.must(source.directory)),
          resolved_dependencies: {}
        )
      end

      # TODO(brrygrdn): Refactor the grapher to wrap the parser call
      parser = Dependabot::FileParsers.for_package_manager(job.package_manager).new(
        dependency_files: files,
        repo_contents_path: job.repo_contents_path,
        source: source,
        credentials: job.credentials,
        reject_external_code: job.reject_external_code?,
        options: job.experiments
      )

      grapher = Dependabot::DependencyGraphers.for_package_manager(job.package_manager).new(
        dependency_files: files,
        dependencies: parser.parse
      )

      GithubApi::DependencySubmission.new(
        job_id: job.id.to_s,
        # FIXME(brrygrdn): We should obtain the ref from git -or- inject it via the backend service
        branch: source.branch || "main",
        sha: base_commit_sha,
        package_manager: job.package_manager,
        manifest_file: grapher.relevant_dependency_file,
        resolved_dependencies: grapher.resolved_dependencies
      )
    end
  end
end
