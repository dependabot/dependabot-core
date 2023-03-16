# frozen_string_literal: true

require "terminal-table"
require "dependabot/api_client"

# This class provides an output adapter for the Dependabot Service which manages
# communication with the private API as well as consolidated error handling.
#
# Currently this is the only output adapter available, but in future we may
# support others for use with the dependabot/cli project.
#
module Dependabot
  class Service
    extend Forwardable
    attr_reader :pull_requests, :errors

    def initialize(client:)
      @client = client
      @pull_requests = []
      @errors = []
    end

    def_delegators :client, :mark_job_as_processed, :update_dependency_list, :record_package_manager_version

    def create_pull_request(dependency_change, base_commit_sha)
      client.create_pull_request(dependency_change, base_commit_sha)
      @pull_requests << [dependency_change.humanized, :created]
    end

    def update_pull_request(dependency_change, base_commit_sha)
      client.update_pull_request(dependency_change, base_commit_sha)
      @pull_requests << [dependency_change.humanized, :updated]
    end

    def close_pull_request(dependency_name, reason)
      client.close_pull_request(dependency_name, reason)
      @pull_requests << [dependency_name, "closed: #{reason}"]
    end

    def record_update_job_error(error_type:, error_details:, dependency: nil)
      @errors << [error_type.to_s, dependency]
      client.record_update_job_error(error_type: error_type, error_details: error_details)
    end

    # This method wraps the Raven client as the Application error tracker
    # the service uses to notice errors.
    #
    # This should be called as an alternative/in addition to record_update_job_error
    # for cases where an error could indicate a problem with the service.
    def capture_exception(error:, job: nil, dependency: nil, tags: {}, extra: {})
      Raven.capture_exception(
        error,
        {
          tags: tags,
          extra: extra.merge({
            update_job_id: job&.id,
            package_manager: job&.package_manager,
            dependency_name: dependency&.name
          }.compact)
        }
      )
    end

    def noop?
      pull_requests.empty? && errors.empty?
    end

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
    def summary
      return if noop?

      [
        "Results:",
        pull_request_summary,
        error_summary,
        job_error_type_summary,
        dependency_error_summary
      ].compact.join("\n")
    end

    private

    attr_reader :client

    def pull_request_summary
      return unless pull_requests.any?

      Terminal::Table.new do |t|
        t.title = "Changes to Dependabot Pull Requests"
        t.rows = pull_requests.map { |deps, action| [action, truncate(deps)] }
      end
    end

    def error_summary
      return unless errors.any?

      "Dependabot encountered '#{errors.length}' error(s) during execution, please check the logs for more details."
    end

    # Example output:
    #
    # +--------------------+
    # |    Errors          |
    # +--------------------+
    # | job_repo_not_found |
    # +--------------------+
    def job_error_type_summary
      job_error_types = errors.filter_map { |error_type, dependency| [error_type] if dependency.nil? }
      return if job_error_types.none?

      Terminal::Table.new do |t|
        t.title = "Errors"
        t.rows = job_error_types
      end
    end

    # Example output:
    #
    # +-------------------------------------+
    # |    Dependencies failed to update    |
    # +---------------------+---------------+
    # | best_dependency_yay | unknown_error |
    # +---------------------+---------------+
    def dependency_error_summary
      dependency_errors = errors.filter_map do |error_type, dependency|
        [dependency.name, error_type] unless dependency.nil?
      end
      return if dependency_errors.none?

      Terminal::Table.new do |t|
        t.title = "Dependencies failed to update"
        t.rows = dependency_errors
      end
    end

    def truncate(string, max: 120)
      snip = max - 3
      string.length > max ? "#{string[0...snip]}..." : string
    end

    def humanize(dependencies)
      dependencies.map do |dependency|
        "#{dependency.name} ( from #{dependency.previous_version} to #{dependency.version} )"
      end.join(", ")
    end
  end
end
