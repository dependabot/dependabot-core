# frozen_string_literal: true

require "http"
require "dependabot/job"

module Dependabot
  class ApiError < StandardError; end

  class ApiClient
    # TODO: instantiate client with job_id?
    def initialize(base_url, token)
      @base_url = base_url
      @token = token
    end

    def get_job(job_id)
      response = fetch_job_details_from_backend(job_id)

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

      Job.new(job_data.merge(token: token))
    end

    def create_pull_request(job_id, dependencies, updated_dependency_files,
                            base_commit_sha, pr_message)
      api_url = "#{base_url}/update_jobs/#{job_id}/create_pull_request"
      data = create_pull_request_data(dependencies, updated_dependency_files, base_commit_sha, pr_message)
      response = http_client.post(api_url, json: { data: data })
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    def update_pull_request(job_id, dependencies, updated_dependency_files,
                            base_commit_sha)
      api_url = "#{base_url}/update_jobs/#{job_id}/update_pull_request"
      body = {
        data: {
          "dependency-names": dependencies.map(&:name),
          "updated-dependency-files": updated_dependency_files,
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

    def close_pull_request(job_id, dependency_name, reason)
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

    def record_update_job_error(job_id, error_type:, error_details:)
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

    def mark_job_as_processed(job_id, base_commit_sha)
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

    def update_dependency_list(job_id, dependencies, dependency_files)
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

    def record_package_manager_version(job_id, ecosystem, package_managers)
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

    attr_reader :token, :base_url

    def http_client
      client = HTTP.auth(token)
      proxy = URI(base_url).find_proxy
      unless proxy.nil?
        args = [proxy.host, proxy.port, proxy.user, proxy.password].compact
        client = client.via(*args)
      end
      client
    end

    def fetch_job_details_from_backend(job_id)
      api_url = "#{base_url}/update_jobs/#{job_id}"
      http_client.get(api_url)
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      # Retry connection errors (which are almost certainly transitory)
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0)) && retry
    end

    def create_pull_request_data(dependencies, updated_dependency_files, base_commit_sha, pr_message)
      data = {
        dependencies: dependencies.map do |dep|
          {
            name: dep.name,
            version: dep.version,
            "previous-version": dep.previous_version,
            requirements: dep.requirements,
            "previous-requirements": dep.previous_requirements
          }
        end,
        "updated-dependency-files": updated_dependency_files,
        "base-commit-sha": base_commit_sha
      }
      return data unless pr_message

      data["commit-message"] = pr_message.commit_message
      data["pr-title"] = pr_message.pr_name
      data["pr-body"] = pr_message.pr_message
      data
    end
  end
end
