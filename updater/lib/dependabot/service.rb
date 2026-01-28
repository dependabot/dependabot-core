# typed: strict
# frozen_string_literal: true

require "sentry-ruby"
require "sorbet-runtime"
require "terminal-table"

require "dependabot/api_client"
require "dependabot/errors"
require "dependabot/opentelemetry"
require "dependabot/experiments"
require "dependabot/telemetry_accumulator"

# This class provides an output adapter for the Dependabot Service which manages
# communication with the private API as well as consolidated error handling.
#
# Currently this is the only output adapter available, but in future we may
# support others for use with the dependabot/cli project.
#
module Dependabot
  class Service
    extend T::Sig
    extend Forwardable

    sig { returns(T::Array[T.untyped]) }
    attr_reader :pull_requests

    sig { returns(T::Array[T::Array[T.untyped]]) }
    attr_reader :errors

    sig { returns(Dependabot::TelemetryAccumulator) }
    attr_reader :telemetry_accumulator

    sig { params(client: Dependabot::ApiClient).void }
    def initialize(client:)
      @client = client
      @pull_requests = T.let([], T::Array[T.untyped])
      @errors = T.let([], T::Array[T::Array[T.untyped]])
      @threads = T.let([], T::Array[T.untyped])
      @telemetry_accumulator = T.let(TelemetryAccumulator.new, Dependabot::TelemetryAccumulator)
    end

    def_delegators :client,
                   :increment_metric

    # Mark job as processed and send all accumulated telemetry in one call
    sig { params(base_commit_sha: String).void }
    def mark_job_as_processed(base_commit_sha)
      telemetry_data = telemetry_accumulator.empty? ? nil : telemetry_accumulator.to_h
      client.mark_job_as_processed(base_commit_sha, telemetry: telemetry_data)
    end

    # Accumulate ecosystem versions for batch sending
    sig { params(ecosystem_versions: T::Hash[Symbol, T.untyped]).void }
    def record_ecosystem_versions(ecosystem_versions)
      telemetry_accumulator.add_ecosystem_versions(ecosystem_versions)
    end

    # Accumulate ecosystem metadata for batch sending
    sig { params(ecosystem: T.nilable(Ecosystem)).void }
    def record_ecosystem_meta(ecosystem)
      return unless Dependabot::Experiments.enabled?(:enable_record_ecosystem_meta)
      return if ecosystem.nil?

      ecosystem_data = {
        ecosystem: {
          name: ecosystem.name,
          package_manager: version_manager_hash(ecosystem.package_manager),
          language: version_manager_hash(ecosystem.language)
        }
      }
      telemetry_accumulator.add_ecosystem_meta(ecosystem_data)
    end

    # Accumulate cooldown metadata for batch sending
    sig { params(job: T.nilable(Dependabot::Job)).void }
    def record_cooldown_meta(job)
      return if job&.cooldown.nil?

      cooldown = T.must(job).cooldown
      cooldown_data = {
        cooldown: {
          ecosystem_name: T.must(job).package_manager,
          config: {
            default_days: T.must(cooldown).default_days,
            semver_major_days: T.must(cooldown).semver_major_days,
            semver_minor_days: T.must(cooldown).semver_minor_days,
            semver_patch_days: T.must(cooldown).semver_patch_days
          }
        }
      }
      telemetry_accumulator.add_cooldown_meta(cooldown_data)
    end

    sig { void }
    def wait_for_calls_to_finish
      return unless Experiments.enabled?("threaded_metadata")

      @threads.each(&:join)
    end

    sig { params(dependency_change: Dependabot::DependencyChange, base_commit_sha: String).void }
    def create_pull_request(dependency_change, base_commit_sha)
      dependency_change.check_dependencies_have_previous_version

      if Experiments.enabled?("threaded_metadata")
        @threads << Thread.new { client.create_pull_request(dependency_change, base_commit_sha) }
      else
        client.create_pull_request(dependency_change, base_commit_sha)
      end
      pull_requests << [dependency_change.humanized, :created]
    end

    sig { params(dependency_change: Dependabot::DependencyChange, base_commit_sha: String).void }
    def update_pull_request(dependency_change, base_commit_sha)
      client.update_pull_request(dependency_change, base_commit_sha)
      pull_requests << [dependency_change.humanized, :updated]
    end

    sig { params(dependencies: T.any(String, T::Array[String]), reason: T.any(String, Symbol)).void }
    def close_pull_request(dependencies, reason)
      client.close_pull_request(dependencies, reason)
      humanized_deps = dependencies.is_a?(String) ? dependencies : dependencies.join(",")
      pull_requests << [humanized_deps, "closed: #{reason}"]
    end

    sig do
      params(
        error_type: T.any(String, Symbol),
        error_details: T.nilable(T::Hash[T.untyped, T.untyped]),
        dependency: T.nilable(Dependabot::Dependency)
      ).void
    end
    def record_update_job_error(error_type:, error_details:, dependency: nil)
      errors << if Dependabot::Experiments.enabled?(:enable_enhanced_error_details_for_updater)
                  [error_type.to_s, error_details, dependency]
                else
                  [error_type.to_s, dependency]
                end
      client.record_update_job_error(error_type: error_type, error_details: error_details)
    end

    sig do
      params(
        warn_type: T.any(String, Symbol),
        warn_title: String,
        warn_description: String
      ).void
    end
    def record_update_job_warning(warn_type:, warn_title:, warn_description:)
      client.record_update_job_warning(
        warn_type: warn_type,
        warn_title: warn_title,
        warn_description: warn_description
      )
    end

    sig { params(error_type: T.any(String, Symbol), error_details: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def record_update_job_unknown_error(error_type:, error_details:)
      client.record_update_job_unknown_error(error_type: error_type, error_details: error_details)
    end

    sig { params(dependency_snapshot: Dependabot::DependencySnapshot).void }
    def update_dependency_list(dependency_snapshot:)
      dependency_payload = dependency_snapshot.all_dependencies.map do |dep|
        {
          name: dep.name,
          version: dep.version,
          requirements: dep.requirements
        }
      end
      dependency_file_paths = dependency_snapshot.all_dependency_files.reject(&:support_file).map(&:path)

      client.update_dependency_list(dependency_payload, dependency_file_paths)
    end

    sig { params(dependency_submission: GithubApi::DependencySubmission).void }
    def create_dependency_submission(dependency_submission:)
      client.create_dependency_submission(dependency_submission.payload)
    end

    # This method wraps the Sentry client as the Application error tracker
    # the service uses to notice errors.
    #
    # This should be called as an alternative/in addition to record_update_job_error
    # for cases where an error could indicate a problem with the service.
    sig do
      params(
        error: StandardError,
        job: T.untyped,
        dependency: T.nilable(Dependabot::Dependency),
        dependency_group: T.nilable(Dependabot::DependencyGroup),
        tags: T::Hash[String, T.untyped]
      ).void
    end
    def capture_exception(error:, job: nil, dependency: nil, dependency_group: nil, tags: {})
      ::Dependabot::OpenTelemetry.record_exception(error: error, job: job, tags: tags)

      # some GHES versions do not support reporting errors to the service
      return unless Experiments.enabled?(:record_update_job_unknown_error)

      error_details = {
        ErrorAttributes::CLASS => error.class.to_s,
        ErrorAttributes::MESSAGE => error.message,
        ErrorAttributes::BACKTRACE => error.backtrace&.join("\n"),
        ErrorAttributes::FINGERPRINT => error.respond_to?(:sentry_context) ? T.unsafe(error).sentry_context[:fingerprint] : nil, # rubocop:disable Layout/LineLength
        ErrorAttributes::PACKAGE_MANAGER => job&.package_manager,
        ErrorAttributes::JOB_ID => job&.id,
        ErrorAttributes::DEPENDENCIES => dependency&.name || job&.dependencies,
        ErrorAttributes::DEPENDENCY_GROUPS => dependency_group&.name || job&.dependency_groups,
        ErrorAttributes::SECURITY_UPDATE => job&.security_updates_only?
      }.compact
      record_update_job_unknown_error(error_type: "unknown_error", error_details: error_details)
    end

    sig { returns(T::Boolean) }
    def noop?
      pull_requests.empty? && errors.empty?
    end

    sig { returns(T::Boolean) }
    def failure?
      errors.any?
    end

    # Example output:
    #
    # +----------------------------+-----------------------------------+
    # |                Changes to Dependabot Pull Requests             |
    # +----------------------------+-----------------------------------+
    # | created                    | package-a ( from 1.0.0 to 1.0.1 ) |
    # | updated                    | package-b ( from 1.1.0 to 1.2.1 ) |
    # | closed:dependency-removed  | package-c                         |
    # +----------------------------+-----------------------------------+
    #
    sig { returns(T.nilable(String)) }
    def summary
      return if noop?

      [
        "Results:",
        pull_request_summary,
        error_summary,
        job_errors_summary,
        dependency_error_summary
      ].compact.join("\n")
    end

    private

    sig { returns(Dependabot::ApiClient) }
    attr_reader :client

    sig { returns(T.nilable(Terminal::Table)) }
    def pull_request_summary
      return unless pull_requests.any?

      T.unsafe(Terminal::Table).new do |t|
        t.title = "Changes to Dependabot Pull Requests"
        t.rows = pull_requests.map { |deps, action| [action, truncate(deps)] }
      end
    end

    sig { returns(T.nilable(String)) }
    def error_summary
      return unless errors.any?

      "Dependabot encountered '#{errors.length}' error(s) during execution, please check the logs for more details."
    end

    # Example output:
    #
    # +------------------------------+
    # |             Errors           |
    # +--------------------+---------+
    # | Type               | Details |
    # +--------------------+---------+
    # | job_repo_not_found | {}      |
    # +--------------------+---------+
    sig { returns(T.nilable(Terminal::Table)) }
    def job_errors_summary
      if Dependabot::Experiments.enabled?(:enable_enhanced_error_details_for_updater)
        job_errors = errors.filter_map do |error_type, error_details, dependency|
          [error_type, JSON.pretty_generate(error_details)] if dependency.nil?
        end
        return if job_errors.none?

        T.unsafe(Terminal::Table).new do |t|
          t.title = "Errors"
          t.headings = %w(Type Details)
          t.rows = job_errors
        end
      else
        job_error_types = errors.filter_map do |error_type, dependency|
          [error_type] if dependency.nil?
        end
        return if job_error_types.none?

        T.unsafe(Terminal::Table).new do |t|
          t.title = "Errors"
          t.rows = job_error_types
        end
      end
    end

    # Example output:
    #
    # +-----------------------------------------------------+
    # |           Dependencies failed to update             |
    # +---------------------+-------------------------------+
    # | Dependency          | Error Type    | Error Details |
    # +---------------------+-------------------------------+
    # | best_dependency_yay | unknown_error | {}            |
    # +---------------------+-------------------------------+
    sig { returns(T.nilable(Terminal::Table)) }
    def dependency_error_summary
      if Dependabot::Experiments.enabled?(:enable_enhanced_error_details_for_updater)
        dependency_errors = errors.filter_map do |error_type, error_details, dependency|
          [dependency.name, error_type, JSON.pretty_generate(error_details)] unless dependency.nil?
        end
        return if dependency_errors.none?

        T.unsafe(Terminal::Table).new do |t|
          t.title = "Dependencies failed to update"
          t.headings = ["Dependency", "Error Type", "Error Details"]
          t.rows = dependency_errors
        end
      else
        dependency_errors = errors.filter_map do |error_type, dependency|
          [dependency.name, error_type] unless dependency.nil?
        end
        return if dependency_errors.none?

        T.unsafe(Terminal::Table).new do |t|
          t.title = "Dependencies failed to update"
          t.rows = dependency_errors
        end
      end
    end

    sig { params(string: String, max: Integer).returns(String) }
    def truncate(string, max: 120)
      snip = max - 3
      string.length > max ? "#{string[0...snip]}..." : string
    end

    sig { params(version_manager: T.nilable(VersionManager)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def version_manager_hash(version_manager)
      return nil if version_manager.nil?

      result = {
        name: version_manager.name,
        raw_version: version_manager.raw_version,
        version: version_manager.version
      }

      if version_manager.requirement
        requirement = version_manager.requirement
        result[:requirement] = {
          raw_constraint: requirement.raw_constraint,
          min_raw_version: requirement.min_raw_version,
          min_version: requirement.min_version,
          max_raw_version: requirement.max_raw_version,
          max_version: requirement.max_version
        }
      end

      result
    end
  end
end
