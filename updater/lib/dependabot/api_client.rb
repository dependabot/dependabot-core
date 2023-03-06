# frozen_string_literal: true

require "http"
require "dependabot/job"

# Provides a client to access the internal Dependabot Service's API
#
# The Service acts as a relay to Core's GitHub API adapters while providing
# some co-ordination and enrichment functionality that is only relevant to
# the integrated service.
#
# This API is only available to Dependabot jobs being executed within our
# hosted infrastructure and is not open to integrators at this time.
#
module Dependabot
  class ApiError < StandardError; end

  class ApiClient
    def initialize(base_url, job_id, job_token)
      @base_url = base_url
      @job_id = job_id
      @job_token = job_token
    end

    # TODO: Remove
    #
    # We don't seem to use this anymore and always read the job description
    # from the file system.
    def fetch_job
      response = fetch_job_details_from_backend

      # If the job has already been accessed then we can safely return quietly.
      # This happens when the backend isn't sure if the updater has enqueued a
      # job (because Heroku served a 500, for example) and enqueues a second to
      # be on the safe side.
      return if response.code == 400 && response.body.include?("been accessed")

      # For other errors from the backend, just raise.
      raise ApiError, response.body if response.code >= 400

      job_data =
        response.parse["data"]["attributes"].
        transform_keys { |k| k.tr("-", "_").to_sym }.
        slice(
          :credentials, :dependencies, :package_manager, :ignore_conditions,
          :existing_pull_requests, :source, :lockfile_only, :allowed_updates,
          :update_subdependencies, :updating_a_pull_request,
          :requirements_update_strategy, :security_advisories,
          :vendor_dependencies, :security_updates_only
        )

      Job.new(job_data.merge(token: job_token))
    end

    # TODO: Make `base_commit_sha` part of Dependabot::DependencyChange
    def create_pull_request(dependency_change, base_commit_sha)
      api_url = "#{base_url}/update_jobs/#{job_id}/create_pull_request"
      data = create_pull_request_data(dependency_change, base_commit_sha)
      response = http_client.post(api_url, json: { data: data })
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    # TODO: Make `base_commit_sha` part of Dependabot::DependencyChange
    # TODO: Determine if we should regenerate the PR message within core for updates
    def update_pull_request(dependency_change, base_commit_sha)
      api_url = "#{base_url}/update_jobs/#{job_id}/update_pull_request"
      body = {
        data: {
          "dependency-names": dependency_change.dependencies.map(&:name),
          "updated-dependency-files": dependency_change.updated_dependency_files,
          "base-commit-sha": base_commit_sha
        }
      }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    def close_pull_request(dependency_name, reason)
      api_url = "#{base_url}/update_jobs/#{job_id}/close_pull_request"
      body = { data: { "dependency-names": dependency_name, reason: reason } }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    def record_update_job_error(error_type:, error_details:)
      api_url = "#{base_url}/update_jobs/#{job_id}/record_update_job_error"
      body = {
        data: {
          "error-type": error_type,
          "error-details": error_details
        }
      }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    def mark_job_as_processed(base_commit_sha)
      api_url = "#{base_url}/update_jobs/#{job_id}/mark_as_processed"
      body = { data: { "base-commit-sha": base_commit_sha } }
      response = http_client.patch(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    def update_dependency_list(dependencies, dependency_files)
      api_url = "#{base_url}/update_jobs/#{job_id}/update_dependency_list"
      body = {
        data: {
          dependencies: dependencies,
          dependency_files: dependency_files
        }
      }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    def record_package_manager_version(ecosystem, package_managers)
      api_url = "#{base_url}/update_jobs/#{job_id}/record_package_manager_version"
      body = {
        data: {
          ecosystem: ecosystem,
          "package-managers": package_managers
        }
      }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    private

    attr_reader :base_url, :job_id, :job_token

    def http_client
      client = HTTP.auth(job_token)
      proxy = URI(base_url).find_proxy
      unless proxy.nil?
        args = [proxy.host, proxy.port, proxy.user, proxy.password].compact
        client = client.via(*args)
      end
      client
    end

    def fetch_job_details_from_backend
      api_url = "#{base_url}/update_jobs/#{job_id}"
      http_client.get(api_url)
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      # Retry connection errors (which are almost certainly transitory)
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    def create_pull_request_data(dependency_change, base_commit_sha)
      data = {
        dependencies: dependency_change.dependencies.map do |dep|
          {
            name: dep.name,
            "previous-version": dep.previous_version,
            requirements: dep.requirements,
            "previous-requirements": dep.previous_requirements
          }.merge({
            version: dep.version,
            removed: dep.removed? ? true : nil
          }.compact)
        end,
        "updated-dependency-files": dependency_change.updated_dependency_files_hash,
        "base-commit-sha": base_commit_sha
      }.merge({
        # TODO: Replace this flag with a group-rule object
        #
        # In future this should be something like:
        #    "group-rule": dependency_change.group_rule_hash
        #
        # This will allow us to pass back the rule id and other parameters
        # to allow Dependabot API to augment PR creation and associate it
        # with the rule for rebasing, etc.
        "grouped-update": dependency_change.grouped_update? ? true : nil
      }.compact)
      return data unless dependency_change.pr_message

      data["commit-message"] = dependency_change.pr_message.commit_message
      data["pr-title"] = dependency_change.pr_message.pr_name
      data["pr-body"] = dependency_change.pr_message.pr_message
      data
    end
  end
end
