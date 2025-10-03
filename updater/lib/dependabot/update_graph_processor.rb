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

      branch = job.source.branch || default_branch

      T.must(job.source.directories).each do |directory|
        directory_source = create_source_for(directory)
        directory_dependency_files = dependency_files_for(directory)

        submission = if directory_dependency_files.empty?
                       empty_submission(branch, directory_source)
                     else
                       create_submission(branch, directory_source, directory_dependency_files)
                     end

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

    sig { params(branch: String, source: Dependabot::Source).returns(GithubApi::DependencySubmission) }
    def empty_submission(branch, source)
      GithubApi::DependencySubmission.new(
        job_id: job.id.to_s,
        branch: branch,
        sha: base_commit_sha,
        package_manager: job.package_manager,
        manifest_file: DependencyFile.new(name: "", content: "", directory: T.must(source.directory)),
        resolved_dependencies: {}
      )
    end

    sig do
      params(
        branch: String,
        source: Dependabot::Source,
        files: T::Array[Dependabot::DependencyFile]
      ).returns(GithubApi::DependencySubmission)
    end
    def create_submission(branch, source, files)
      parser = Dependabot::FileParsers.for_package_manager(job.package_manager).new(
        dependency_files: files,
        repo_contents_path: job.repo_contents_path,
        source: source,
        credentials: job.credentials,
        reject_external_code: job.reject_external_code?,
        options: job.experiments
      )

      grapher = Dependabot::DependencyGraphers.for_package_manager(job.package_manager).new(file_parser: parser)
      grapher.prepare!

      GithubApi::DependencySubmission.new(
        job_id: job.id.to_s,
        branch: branch,
        sha: base_commit_sha,
        package_manager: job.package_manager,
        manifest_file: grapher.relevant_dependency_file,
        resolved_dependencies: grapher.resolved_dependencies
      )
    end

    sig { returns(String) }
    def default_branch
      return fetch_default_branch_from_github if job.source.provider == "github"

      Dependabot.logger.warn(
        "Dependency submissions are not fully support for provider '#{job.source.provider}'. " \
        "Substituting 'main' as default branch."
      )
      "main"
    end

    sig { returns(String) }
    def fetch_default_branch_from_github
      @fetch_default_branch_from_github ||= T.let(
        github_client.fetch_default_branch(job.source.repo),
        T.nilable(String)
      )
    rescue Octokit::NotFound
      # This is unlikely to happen, but if it does it means the repository has been deleted
      # while we are working, so let's handle it properly.
      raise Dependabot::RepoNotFound, job.source
    end

    sig { returns(Dependabot::Clients::GithubWithRetries) }
    def github_client
      @github_client ||=
        T.let(
          Dependabot::Clients::GithubWithRetries.for_source(
            source: job.source,
            credentials: job.credentials
          ),
          T.nilable(Dependabot::Clients::GithubWithRetries)
        )
    end
  end
end
