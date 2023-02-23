# frozen_string_literal: true

require "terminal-table"
require "dependabot/api_client"

# Wraps an API client with the current state of communications with the Dependabot Service
# and provides an interface to summarise all actions taken.
#
module Dependabot
  class Service
    extend Forwardable
    attr_reader :client, :events, :pull_requests, :errors

    def initialize(client:)
      @client = client
      @pull_requests = []
      @errors = []
    end

    def_delegators :client, :get_job, :mark_job_as_processed, :update_dependency_list, :record_package_manager_version

    # rubocop:disable Metrics:ParameterLists
    def create_pull_request(job_id, dependencies, updated_dependency_files, base_commit_sha, pr_message,
                            grouped_update = false)
      client.create_pull_request(
        job_id,
        dependencies,
        updated_dependency_files,
        base_commit_sha,
        pr_message,
        grouped_update
      )
      @pull_requests << [humanize(dependencies), :created]
    end
    # rubocop:enable Metrics:ParameterLists

    def update_pull_request(job_id, dependencies, updated_dependency_files, base_commit_sha)
      client.update_pull_request(job_id, dependencies, updated_dependency_files, base_commit_sha)
      @pull_requests << [humanize(dependencies), :updated]
    end

    def close_pull_request(job_id, dependency_name, reason)
      client.close_pull_request(job_id, dependency_name, reason)
      @pull_requests << [dependency_name, "closed: #{reason}"]
    end

    def record_update_job_error(job_id, error_type:, error_details:)
      @errors << error_type.to_s
      client.record_update_job_error(job_id, error_type: error_type, error_details: error_details)
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
        error_summary
      ].compact.join("\n")
    end

    private

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
