# typed: strict
# frozen_string_literal: true

require "base64"
require "dependabot/base_command"
require "dependabot/errors"
require "dependabot/opentelemetry"
require "dependabot/updater"
require "octokit"

require "sorbet-runtime"

module Dependabot
  class FileFetcherCommand < BaseCommand
    extend T::Sig
    # BaseCommand does not implement this method, so we should expose
    # the instance variable for error handling to avoid raising a
    # NotImplementedError if it is referenced
    sig { returns(T.nilable(String)) }
    attr_reader :base_commit_sha

    sig { void }
    def initialize()
      @base_commit_sha = T.let(nil, T.nilable(String))
    end

    sig { override.void }
    def perform_job # rubocop:disable Metrics/PerceivedComplexity,Metrics/AbcSize
      @base_commit_sha = nil

      Dependabot.logger.info("Job definition: #{File.read(Environment.job_path)}") if Environment.job_path
      ::Dependabot::OpenTelemetry.tracer.in_span("file_fetcher", kind: :internal) do |span|
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id.to_s)

        begin
          connectivity_check if ENV["ENABLE_CONNECTIVITY_CHECK"] == "1"
          clone_repo_contents
          @base_commit_sha = file_fetcher.commit
          raise "base commit SHA not found" unless @base_commit_sha

          # In the older versions of GHES (> 3.11.0) job.source.directories will be nil as source.directories was
          # introduced after 3.11.0 release. So, this also supports backward compatibility for older versions of GHES.
          if job.source.directories
            dependency_files_for_multi_directories
          else
            dependency_files
          end
        rescue StandardError => e
          @base_commit_sha ||= "unknown"
          if Octokit::RATE_LIMITED_ERRORS.include?(e.class)
            remaining = rate_limit_error_remaining(e)
            Dependabot.logger.error("Repository is rate limited, attempting to retry in " \
                                    "#{remaining}s")
          else
            Dependabot.logger.error("Error during file fetching; aborting: #{e.message}")
          end
          handle_file_fetcher_error(e)
          service.mark_job_as_processed(@base_commit_sha)
          return nil
        end

        Dependabot.logger.info("Base commit SHA: #{@base_commit_sha}")
        File.write(Environment.output_path, JSON.dump(
                                              base64_dependency_files: base64_dependency_files.map(&:to_h),
                                              base_commit_sha: @base_commit_sha
                                            ))

        save_job_details
      end
    end

    private

    sig { void }
    def save_job_details
      # TODO: Use the Dependabot::Environment helper for this
      return unless ENV["UPDATER_ONE_CONTAINER"]

      File.write(Environment.job_path, JSON.dump(
                                         base64_dependency_files: base64_dependency_files.map(&:to_h),
                                         base_commit_sha: @base_commit_sha,
                                         job: Environment.job_definition["job"]
                                       ))
    end

    # A method that abstracts the file fetcher creation logic and applies the same settings across all instances
    sig { params(directory: T.nilable(String)).returns(FileFetchers::Base) }
    def create_file_fetcher(directory: nil)
      # Use the provided directory or fallback to job.source.directory if directory is nil.
      directory_to_use = directory || job.source.directory

      args = {
        source: job.source.clone.tap { |s| s.directory = directory_to_use },
        credentials: Environment.job_definition.fetch("credentials", []),
        options: job.experiments
      }
      args[:repo_contents_path] = Environment.repo_contents_path if job.clone? || already_cloned?
      Dependabot::FileFetchers.for_package_manager(job.package_manager).new(**args)
    end

    # The main file fetcher method that now calls the create_file_fetcher method
    # and ensures it uses the same repo_contents_path setting as others.
    sig { returns(FileFetchers::Base) }
    def file_fetcher
      @file_fetcher ||= T.let(create_file_fetcher, T.nilable(FileFetchers::Base))
    end

    # This method is responsible for creating or retrieving a file fetcher
    # from a cache (@file_fetchers) for the given directory.
    sig { params(directory: String).returns(Dependabot::FileFetchers::Base) }
    def file_fetcher_for_directory(directory)
      @file_fetchers ||= T.let({}, T.nilable(T::Hash[String, FileFetchers::Base]))
      @file_fetchers[directory] ||= create_file_fetcher(directory: directory)
    end

    sig { returns(T::Array[DependencyFile]) }
    def dependency_files_for_multi_directories
      if Dependabot::Experiments.enabled?(:globs)
        return @dependency_files_for_multi_directories ||= dependency_files_for_globs
      end

      @dependency_files_for_multi_directories ||= T.let(T.must(job.source.directories).flat_map do |dir|
        ff = file_fetcher_with_retries { file_fetcher_for_directory(dir) }
        files = ff.files
        post_ecosystem_versions(ff) if should_record_ecosystem_versions?
        files
      end, T.nilable(T::Array[DependencyFile]))
    end

    sig { returns(T::Array[DependencyFile]) }
    def dependency_files_for_globs
      has_glob = T.let(false, T::Boolean)
      directories = Dir.chdir(T.must(job.repo_contents_path)) do
        T.must(job.source.directories).map do |dir|
          next dir unless glob?(dir)

          has_glob = true
          dir = dir.delete_prefix("/")
          Dir.glob(dir, File::FNM_DOTMATCH).select { |d| File.directory?(d) }.map { |d| "/#{d}" }
        end.flatten
      end.uniq

      directories.flat_map do |dir|
        ff = file_fetcher_with_retries { file_fetcher_for_directory(dir) }

        begin
          files = ff.files
        rescue Dependabot::DependencyFileNotFound
          # skip directories that don't contain manifests if globbing is used
          next if has_glob

          raise
        end

        post_ecosystem_versions(ff) if should_record_ecosystem_versions?
        files
      end.compact
    end

    sig { returns(T::Array[DependencyFile]) }
    def dependency_files
      return @dependency_files if defined?(@dependency_files) && !@dependency_files.nil?

      @dependency_files = T.let(with_retries { file_fetcher.files }, T.nilable(T::Array[DependencyFile]))
      post_ecosystem_versions(file_fetcher) if should_record_ecosystem_versions?
      T.must(@dependency_files)
    end

    sig { returns(T::Boolean) }
    def should_record_ecosystem_versions?
      # We don't set this flag in GHES because there's no point in recording versions since we can't access that data.
      Experiments.enabled?(:record_ecosystem_versions)
    end

    sig { params(file_fetcher: FileFetchers::Base).void }
    def post_ecosystem_versions(file_fetcher)
      ecosystem_versions = file_fetcher.ecosystem_versions
      api_client.record_ecosystem_versions(ecosystem_versions) unless ecosystem_versions.nil?
    end

    sig { params(blk: T.proc.returns(FileFetchers::Base)).returns(FileFetchers::Base) }
    def file_fetcher_with_retries(&blk)
      retries ||= 0
      begin
        yield
      rescue Octokit::BadGateway
        retries += 1
        retry if retries <= 2
        raise
      end
    end

    sig { params(blk: T.proc.returns(T::Array[DependencyFile])).returns(T::Array[DependencyFile]) }
    def with_retries(&blk)
      retries ||= 0
      begin
        yield
      rescue Octokit::BadGateway
        retries += 1
        retry if retries <= 2
        raise
      end
    end

    sig { void }
    def clone_repo_contents
      return unless job.clone?

      file_fetcher.clone_repo_contents
    end

    sig { returns(T::Array[DependencyFile]) }
    def base64_dependency_files
      files = job.source.directories ? dependency_files_for_multi_directories : dependency_files
      files.map do |file|
        base64_file = file.dup
        base64_file.content = Base64.encode64(T.must(file.content)) unless file.binary?
        base64_file
      end
    end

    sig { override.returns(Dependabot::Job) }
    def job
      @job ||= T.let(
        Job.new_fetch_job(
          job_id: job_id,
          job_definition: Environment.job_definition,
          repo_contents_path: Environment.repo_contents_path
        ),
        T.nilable(Job)
      )
    end

    sig { returns(T::Boolean) }
    def already_cloned?
      return false unless Environment.repo_contents_path

      # For testing, the source repo may already be mounted.
      @already_cloned ||= T.let(
        File.directory?(File.join(Environment.repo_contents_path, ".git")),
        T.nilable(T::Boolean)
      )
    end

    sig { params(error: StandardError).void }
    def handle_file_fetcher_error(error)
      error_details = Dependabot.fetcher_error_details(error)

      if error_details.nil?
        log_error(error)

        unknown_error_details = {
          ErrorAttributes::CLASS => error.class.to_s,
          ErrorAttributes::MESSAGE => error.message,
          ErrorAttributes::BACKTRACE => error.backtrace&.join("\n"),
          ErrorAttributes::FINGERPRINT => error.respond_to?(:sentry_context) ?
            T.unsafe(error).sentry_context[:fingerprint] : nil,
          ErrorAttributes::PACKAGE_MANAGER => job.package_manager,
          ErrorAttributes::JOB_ID => job.id,
          ErrorAttributes::DEPENDENCIES => job.dependencies,
          ErrorAttributes::DEPENDENCY_GROUPS => job.dependency_groups
        }.compact

        error_details = {
          "error-type": "file_fetcher_error",
          "error-detail": unknown_error_details
        }
      end

      service.record_update_job_error(
        error_type: error_details.fetch(:"error-type"),
        error_details: error_details[:"error-detail"]
      )

      return unless error_details.fetch(:"error-type") == "file_fetcher_error"

      service.capture_exception(error: error, job: job)
    end

    sig { params(error: StandardError).returns(Float) }
    def rate_limit_error_remaining(error)
      clientError = T.cast(error, Octokit::ClientError)
      # Time at which the current rate limit window resets in UTC epoch secs.
      expires_at = clientError.response_headers["X-RateLimit-Reset"].to_i
      remaining = Time.at(expires_at) - Time.now
      remaining.positive? ? remaining : 0.0
    end

    sig { params(error: StandardError).void }
    def log_error(error)
      Dependabot.logger.error(error.message)
      error.backtrace&.each { |line| Dependabot.logger.error line }
    end

    sig { params(error_details: T.untyped).void }
    def record_error(error_details)
      service.record_update_job_error(
        error_type: error_details.fetch(:"error-type"),
        error_details: error_details[:"error-detail"]
      )

      # We don't set this flag in GHES because there older GHES version does not support reporting unknown errors.
      return unless Experiments.enabled?(:record_update_job_unknown_error)
      return unless error_details.fetch(:"error-type") == "file_fetcher_error"

      service.record_update_job_unknown_error(
        error_type: error_details.fetch(:"error-type"),
        error_details: error_details[:"error-detail"]
      )
    end

    # Perform a debug check of connectivity to GitHub/GHES. This also ensures
    # connectivity through the proxy is established which can take 10-15s on
    # the first request in some customer's environments.
    sig { void }
    def connectivity_check
      Dependabot.logger.info("Connectivity check starting")
      github_connectivity_client(job).repository(job.source.repo)
      Dependabot.logger.info("Connectivity check successful")
    rescue StandardError => e
      Dependabot.logger.error("Connectivity check failed: #{e.message}")
    end

    sig { params(job: Job).returns(Octokit::Client) }
    def github_connectivity_client(job)
      Octokit::Client.new({
        api_endpoint: job.source.api_endpoint,
        connection_options: {
          request: {
            open_timeout: 20,
            timeout: 5
          }
        }
      })
    end

    sig { params(directory: String).returns(T::Boolean) }
    def glob?(directory)
      # We could tighten this up, but it's probably close enough.
      directory.include?("*") || directory.include?("?") || (directory.include?("[") && directory.include?("]"))
    end
  end
end
