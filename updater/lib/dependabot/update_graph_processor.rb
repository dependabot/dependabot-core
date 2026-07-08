# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

# Dependabot components
require "dependabot/environment"
require "dependabot/errors"
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

    UNEXPECTED_EXTERNAL_CODE_MESSAGE = <<~MSG
      Dependabot refused to execute external code

      This directory is configured to use a private registry but does not allow insecure code execution via your Dependabot configuration.

      Please set `insecure-external-code-execution: allow` in the config if you trust your dependencies' supply chain or remove the private registry from this directory.
    MSG

    # To do work, this class needs three arguments:
    # - The Dependabot::Service to send events and outcomes to
    # - The Dependabot::Job that describes the work to be done
    # - The Dependabot::DependencyFile list retrieved by the file fetcher
    # - The base_commit_sha being processed
    # - Optionally, a map of directory to a non-fatal fetch error (e.g. an
    #   unresolvable path dependency) to report as a degraded snapshot
    sig do
      params(
        service: Dependabot::Service,
        job: Dependabot::Job,
        base_commit_sha: String,
        dependency_files: T::Array[Dependabot::DependencyFile],
        directory_fetch_errors: T::Hash[String, Dependabot::DependabotError]
      ).void
    end
    def initialize(service:, job:, base_commit_sha:, dependency_files:, directory_fetch_errors: {})
      @service = service
      @job = job
      @base_commit_sha = base_commit_sha
      @dependency_files = dependency_files
      @directory_fetch_errors = directory_fetch_errors

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
        # Each directory is processed with its own error handling so one failure will not
        # block the overall job.
        process_directory(branch:, directory:)
      end
    rescue StandardError => e
      service.record_workflow_result(
        directory: "(unknown)",
        status: GithubApi::DependencySubmission::SnapshotStatus::FAILED.serialize,
        details: "unexpected error: #{e.class}"
      )
      raise
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

    sig { returns(T::Hash[String, Dependabot::DependabotError]) }
    attr_reader :directory_fetch_errors

    sig { returns(Dependabot::Updater::ErrorHandler) }
    attr_reader :error_handler

    sig { params(branch: String, directory: String).void }
    def process_directory(branch:, directory:) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
      directory_source = create_source_for(directory)

      # A non-fatal fetch error (e.g. an unresolvable path dependency) means we
      # could not fetch this directory's files, but the rest of the job proceeded.
      # Report it as a skipped snapshot describing the failure rather than a
      # misleading "no manifests" skip.
      if (fetch_error = directory_fetch_errors[directory])
        submit_skipped_fetch_error(branch, directory, directory_source, fetch_error)
        return
      end

      directory_dependency_files = dependency_files_for(directory)

      submission = if directory_dependency_files.empty?
                     empty_submission(
                       branch,
                       directory_source,
                       GithubApi::DependencySubmission::SnapshotStatus::SKIPPED,
                       GithubApi::DependencySubmission::EMPTY_REASON_NO_MANIFESTS
                     )
                   else
                     create_submission(branch, directory_source, directory_dependency_files)
                   end

      Dependabot.logger.info("Dependency submission payload:\n#{JSON.pretty_generate(submission.payload)}")
      service.create_dependency_submission(dependency_submission: submission)

      record_workflow_result(
        directory,
        submission.status,
        "Found #{submission.resolved_dependencies.size} dependencies"
      )
    rescue Dependabot::UnexpectedExternalCode
      # If this has been raised, then the directory is trying to use a private registry with an ecosystem
      # that requires the `insecure-external-code-execution: allow` flag.
      #
      # The default policy is denied, so this outcome represents a misconfiguration for the directory.
      # We should record this failure and allow other directories in the job to continue, as they may
      # not be misconfigured.
      Dependabot.logger.info("Skipping directory #{directory} — #{UNEXPECTED_EXTERNAL_CODE_MESSAGE}")

      # Emit a warning rather than an error since this is a misconfiguration the user needs to fix.
      service.record_update_job_warning(
        warn_type: "unexpected_external_code",
        warn_title: "Refusing to execute external code",
        warn_description: "Cannot process directory #{directory} without external code execution"
      )

      return unless Dependabot::Environment.github_actions?

      service.create_dependency_submission(
        dependency_submission: empty_submission(
          branch,
          T.must(directory_source),
          GithubApi::DependencySubmission::SnapshotStatus::FAILED,
          "unexpected_external_code"
        )
      )

      record_workflow_result(
        directory,
        GithubApi::DependencySubmission::SnapshotStatus::FAILED,
        UNEXPECTED_EXTERNAL_CODE_MESSAGE
      )
    rescue Dependabot::ApiError, Excon::Error::Socket, Excon::Error::Timeout, OpenSSL::SSL::SSLError
      # If the submission API is down, we should raise this as a specific error type for visibility.
      error_handler.handle_job_error(
        error: Dependabot::SnapshotsUnavailableGraphError.new(
          "Unable to submit data to the Dependency Snapshot API"
        )
      )

      record_workflow_result(
        directory,
        GithubApi::DependencySubmission::SnapshotStatus::FAILED,
        "Unable to submit data to the Dependency Snapshot API"
      )
    rescue Dependabot::DependabotError => e
      error_handler.handle_job_error(error: e)

      # If we are not running in Actions, there's nothing more to do.
      return unless Dependabot::Environment.github_actions?

      error_details = Dependabot.updater_error_details(e) || { "error-type": "unknown_error" }
      error_detail = T.cast(error_details[:"error-detail"], T.nilable(T::Hash[Symbol, T.anything]))
      detail_message = T.cast(error_detail&.dig(:message), T.nilable(Object))
      record_workflow_result(
        directory,
        GithubApi::DependencySubmission::SnapshotStatus::FAILED,
        detail_message.is_a?(String) ? detail_message : "An unknown error occurred, please check the logs for details."
      )

      # Send an empty submission so the snapshot service has a record that the job id has been completed.
      empty_submission = empty_submission(
        branch,
        T.must(directory_source),
        GithubApi::DependencySubmission::SnapshotStatus::FAILED,
        T.cast(error_details.fetch(:"error-type"), String)
      )
      service.create_dependency_submission(dependency_submission: empty_submission)
    end

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

    # Submits a skipped snapshot for a directory whose files could not be fetched
    # due to a non-fatal error (e.g. an unresolvable path dependency). The snapshot
    # carries the failure reason so consumers can distinguish it from a directory
    # that genuinely has no manifests.
    sig do
      params(
        branch: String,
        directory: String,
        source: Dependabot::Source,
        error: Dependabot::DependabotError
      ).void
    end
    def submit_skipped_fetch_error(branch, directory, source, error)
      reason = skipped_reason_for(error)

      Dependabot.logger.warn("Dependency graph incomplete in directory #{directory}: #{error.message}")

      service.record_update_job_warning(
        warn_type: "dependency_graph_incomplete",
        warn_title: "dependency graph incomplete",
        warn_description: "The dependency graph may be incomplete. #{error.message}"
      )

      submission = empty_submission(
        branch,
        source,
        GithubApi::DependencySubmission::SnapshotStatus::SKIPPED,
        reason
      )
      Dependabot.logger.info("Dependency submission payload:\n#{JSON.pretty_generate(submission.payload)}")
      service.create_dependency_submission(dependency_submission: submission)

      record_workflow_result(
        directory,
        GithubApi::DependencySubmission::SnapshotStatus::SKIPPED,
        reason
      )
    end

    sig { params(error: Dependabot::DependabotError).returns(String) }
    def skipped_reason_for(error)
      case error
      when Dependabot::PathDependenciesNotReachable
        GithubApi::DependencySubmission::SKIPPED_REASON_PATH_DEPENDENCIES_NOT_REACHABLE
      else
        error.message
      end
    end

    sig do
      params(
        branch: String,
        source: Dependabot::Source,
        status: GithubApi::DependencySubmission::SnapshotStatus,
        reason: T.nilable(String)
      ).returns(GithubApi::DependencySubmission)
    end
    def empty_submission(branch, source, status, reason)
      GithubApi::DependencySubmission.new(
        job_id: job.id.to_s,
        branch: branch,
        sha: base_commit_sha,
        package_manager: job.package_manager,
        manifest_snapshots: [
          Dependabot::DependencyGraphers::ManifestGroupSnapshot.new(
            manifest_file: DependencyFile.new(name: "", content: "", directory: T.must(source.directory)),
            resolved_dependencies: {}
          )
        ],
        status: status,
        reason: reason
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

      # Produce the manifest snapshots so any error flags are set on the grapher
      manifest_group_snapshots = grapher.manifest_group_snapshots

      # If any non-fatal errors were captured during the parse, mark the snapshot as degraded.
      if grapher.errored_fetching_subdependencies
        handle_subdependency_error(grapher.subdependency_error, source)
        status = GithubApi::DependencySubmission::SnapshotStatus::DEGRADED
        reason = GithubApi::DependencySubmission::DEGRADED_REASON_SUBDEPENDENCY_ERR
      end

      GithubApi::DependencySubmission.new(
        job_id: job.id.to_s,
        branch: branch,
        sha: base_commit_sha,
        package_manager: job.package_manager,
        manifest_snapshots: manifest_group_snapshots,
        status: status || GithubApi::DependencySubmission::SnapshotStatus::SUCCESS,
        reason: reason || nil
      )
    end

    sig { params(error: T.nilable(StandardError), source: Dependabot::Source).void }
    def handle_subdependency_error(error, source)
      # We record a warning instead of an error because the graph submission can still proceed
      # with partial data - only the subdependency relationships will be missing.
      error_message = if error.is_a?(Dependabot::DependabotError)
                        error.message
                      else
                        "Failed to fetch subdependencies in directory #{source.directory}"
                      end

      Dependabot.logger.warn("Dependency graph incomplete: #{error_message}")

      service.record_update_job_warning(
        warn_type: "dependency_graph_incomplete",
        warn_title: "dependency graph incomplete",
        warn_description: "The dependency graph may be incomplete. #{error_message}"
      )

      service.record_workflow_result(
        directory: T.must(source.directory),
        status: GithubApi::DependencySubmission::SnapshotStatus::DEGRADED.serialize,
        details: <<~MSG
          The dependency graph may be incomplete: #{error_message}
        MSG
      )
    end

    sig { params(error: T.nilable(StandardError), source: Dependabot::Source).void }
    def record_subdependency_error(error, source)
      if error.is_a?(Dependabot::DependabotError)
        error_handler.handle_job_error(error: error)
      else
        error_handler.handle_job_error(
          error: Dependabot::DependencyFileNotResolvable.new(
            "Failed to fetch subdependencies in directory #{source.directory}"
          )
        )
      end
    end

    sig { returns(String) }
    def default_branch
      SharedHelpers.with_git_configured(credentials: job.credentials) do
        Dir.chdir(T.must(job.repo_contents_path)) do
          branch = SharedHelpers.run_shell_command(
            "git symbolic-ref --short refs/remotes/origin/HEAD",
            stderr_to_stdout: false
          )
          branch.strip.sub("origin/", "refs/heads/")
        end
      end
    end

    sig do
      params(
        directory: String,
        status: GithubApi::DependencySubmission::SnapshotStatus,
        details: String
      ).void
    end
    def record_workflow_result(directory, status, details)
      service.record_workflow_result(
        directory: directory,
        status: status.serialize,
        details: details
      )
    end
  end
end
