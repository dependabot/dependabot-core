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
          "dependency-names": dependency_change.updated_dependencies.map(&:name),
          "updated-dependency-files": dependency_change.updated_dependency_files_hash,
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

    def increment_metric(metric, tags:)
      api_url = "#{base_url}/update_jobs/#{job_id}/increment_metric"
      body = {
        data: {
          metric: metric,
          tags: tags
        }
      }
      response = http_client.post(api_url, json: body)
      # We treat metrics as fire-and-forget, so just warn if they fail.
      Dependabot.logger.debug("Unable to report metric '#{metric}'.") if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      Dependabot.logger.debug("Unable to report metric '#{metric}'.")
    end

    private

    attr_reader :base_url, :job_id, :job_token

    def http_client
      client = HTTP.auth(job_token)
      proxy = ENV["HTTPS_PROXY"] ? URI(ENV["HTTPS_PROXY"]) : URI(base_url).find_proxy
      unless proxy.nil?
        args = [proxy.host, proxy.port, proxy.user, proxy.password].compact
        client = client.via(*args)
      end
      client
    end

    def dependency_group_hash(dependency_change)
      return {} unless dependency_change.grouped_update?

      # FIXME: We currently assumpt that _an attempt_ to send a DependencyGroup#id should
      # result in the `grouped-update` flag being set, regardless of whether the
      # DependencyGroup actually exists.
      { "dependency-group": dependency_change.dependency_group.to_h }.compact
    end

    def create_pull_request_data(dependency_change, base_commit_sha)
      data = {
        dependencies: dependency_change.updated_dependencies.map do |dep|
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
      }.merge(dependency_group_hash(dependency_change))

      return data unless dependency_change.pr_message

      data["commit-message"] = dependency_change.pr_message.commit_message
      data["pr-title"] = dependency_change.pr_message.pr_name
      data["pr-body"] = dependency_change.pr_message.pr_message
      data
    end
  end
end
