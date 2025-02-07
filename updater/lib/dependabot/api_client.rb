# typed: strict
# frozen_string_literal: true

require "http"
require "dependabot/job"
require "dependabot/opentelemetry"
require "sorbet-runtime"
require "dependabot/errors"

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

  class ApiClient # rubocop:disable Metrics/ClassLength
    extend T::Sig

    MAX_REQUEST_RETRIES = 3
    INVALID_REQUEST_MSG = /The request contains invalid or unauthorized changes/

    sig { params(base_url: String, job_id: T.any(String, Integer), job_token: String).void }
    def initialize(base_url, job_id, job_token)
      @base_url = base_url
      @job_id = job_id
      @job_token = job_token
    end

    # TODO: Make `base_commit_sha` part of Dependabot::DependencyChange
    sig { params(dependency_change: Dependabot::DependencyChange, base_commit_sha: String).void }
    def create_pull_request(dependency_change, base_commit_sha)
      ::Dependabot::OpenTelemetry.tracer.in_span("create_pull_request", kind: :internal) do |span|
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id.to_s)
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::BASE_COMMIT_SHA, base_commit_sha)
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::DEPENDENCY_NAMES, dependency_change.humanized)

        api_url = "#{base_url}/update_jobs/#{job_id}/create_pull_request"
        data = create_pull_request_data(dependency_change, base_commit_sha)
        response = http_client.post(api_url, json: { data: data })

        if response.code >= 400 && dependency_file_not_supported_error?(response.body.to_s)
          raise Dependabot::DependencyFileNotSupported, response.body.to_s
        elsif response.code >= 400
          raise ApiError, response.body
        end
      rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
        retry_count ||= 0
        retry_count += 1
        raise if retry_count > MAX_REQUEST_RETRIES

        sleep(rand(3.0..10.0))
        retry
      end
    end

    # TODO: Make `base_commit_sha` part of Dependabot::DependencyChange
    # TODO: Determine if we should regenerate the PR message within core for updates
    sig { params(dependency_change: Dependabot::DependencyChange, base_commit_sha: String).void }
    def update_pull_request(dependency_change, base_commit_sha)
      ::Dependabot::OpenTelemetry.tracer.in_span("update_pull_request", kind: :internal) do |span|
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id.to_s)
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::BASE_COMMIT_SHA, base_commit_sha)
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::DEPENDENCY_NAMES, dependency_change.humanized)

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
        raise if retry_count > MAX_REQUEST_RETRIES

        sleep(rand(3.0..10.0))
        retry
      end
    end

    sig { params(dependency_names: T.any(String, T::Array[String]), reason: T.any(String, Symbol)).void }
    def close_pull_request(dependency_names, reason)
      ::Dependabot::OpenTelemetry.tracer.in_span("close_pull_request", kind: :internal) do |span|
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id.to_s)
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::PR_CLOSE_REASON, reason.to_s)

        api_url = "#{base_url}/update_jobs/#{job_id}/close_pull_request"
        body = { data: { "dependency-names": dependency_names, reason: reason } }
        response = http_client.post(api_url, json: body)
        raise ApiError, response.body if response.code >= 400
      rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
        retry_count ||= 0
        retry_count += 1
        raise if retry_count > MAX_REQUEST_RETRIES

        sleep(rand(3.0..10.0))
        retry
      end
    end

    sig { params(error_type: T.any(String, Symbol), error_details: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def record_update_job_error(error_type:, error_details:)
      ::Dependabot::OpenTelemetry.tracer.in_span("record_update_job_error", kind: :internal) do |_span|
        ::Dependabot::OpenTelemetry.record_update_job_error(
          job_id: job_id,
          error_type: error_type,
          error_details: error_details
        )
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
        raise if retry_count > MAX_REQUEST_RETRIES

        sleep(rand(3.0..10.0))
        retry
      end
    end

    sig do
      params(
        warn_type: T.any(String, Symbol),
        warn_title: String,
        warn_description: String
      ).void
    end
    def record_update_job_warning(warn_type:, warn_title:, warn_description:)
      ::Dependabot::OpenTelemetry.tracer.in_span("record_update_job_message", kind: :internal) do |_span|
        ::Dependabot::OpenTelemetry.record_update_job_warning(
          job_id: job_id,
          warn_type: warn_type,
          warn_title: warn_title,
          warn_description: warn_description
        )
        api_url = "#{base_url}/update_jobs/#{job_id}/record_update_job_warning"
        body = {
          data: {
            "warn-type": warn_type,
            "warn-title": warn_title,
            "warn-description": warn_description
          }
        }
        response = http_client.post(api_url, json: body)
        raise ApiError, response.body if response.code >= 400
      rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
        retry_count ||= 0
        retry_count += 1
        raise if retry_count > MAX_REQUEST_RETRIES

        sleep(rand(3.0..10.0))
        retry
      end
    end

    sig { params(error_type: T.any(Symbol, String), error_details: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def record_update_job_unknown_error(error_type:, error_details:)
      error_type = "unknown_error" if error_type.nil?
      ::Dependabot::OpenTelemetry.tracer.in_span("record_update_job_unknown_error", kind: :internal) do |_span|
        ::Dependabot::OpenTelemetry.record_update_job_error(job_id: job_id, error_type: error_type,
                                                            error_details: error_details)

        api_url = "#{base_url}/update_jobs/#{job_id}/record_update_job_unknown_error"
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
        raise if retry_count > MAX_REQUEST_RETRIES

        sleep(rand(3.0..10.0))
        retry
      end
    end

    sig { params(base_commit_sha: String).void }
    def mark_job_as_processed(base_commit_sha)
      ::Dependabot::OpenTelemetry.tracer.in_span("mark_job_as_processed", kind: :internal) do |span|
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::BASE_COMMIT_SHA, base_commit_sha)
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id.to_s)

        api_url = "#{base_url}/update_jobs/#{job_id}/mark_as_processed"
        body = { data: { "base-commit-sha": base_commit_sha } }
        response = http_client.patch(api_url, json: body)
        raise ApiError, response.body if response.code >= 400
      rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
        retry_count ||= 0
        retry_count += 1
        raise if retry_count > MAX_REQUEST_RETRIES

        sleep(rand(3.0..10.0))
        retry
      end
    end

    sig { params(dependencies: T::Array[T::Hash[Symbol, T.untyped]], dependency_files: T::Array[String]).void }
    def update_dependency_list(dependencies, dependency_files)
      ::Dependabot::OpenTelemetry.tracer.in_span("update_dependency_list", kind: :internal) do |span|
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id.to_s)

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
        raise if retry_count > MAX_REQUEST_RETRIES

        sleep(rand(3.0..10.0))
        retry
      end
    end

    sig { params(ecosystem_versions: T::Hash[Symbol, T.untyped]).void }
    def record_ecosystem_versions(ecosystem_versions)
      ::Dependabot::OpenTelemetry.tracer.in_span("record_ecosystem_versions", kind: :internal) do |_span|
        api_url = "#{base_url}/update_jobs/#{job_id}/record_ecosystem_versions"
        body = {
          data: { ecosystem_versions: ecosystem_versions }
        }
        response = http_client.post(api_url, json: body)
        raise ApiError, response.body if response.code >= 400
      rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
        retry_count ||= 0
        retry_count += 1
        raise if retry_count > MAX_REQUEST_RETRIES

        sleep(rand(3.0..10.0))
        retry
      end
    end

    sig { params(metric: String, tags: T::Hash[String, String]).void }
    def increment_metric(metric, tags:)
      ::Dependabot::OpenTelemetry.tracer.in_span("increment_metric", kind: :internal) do |span|
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID.to_s, job_id.to_s)
        span.set_attribute(::Dependabot::OpenTelemetry::Attributes::METRIC.to_s, metric)
        tags.each do |key, value|
          span.set_attribute(key.to_s, value.to_s)
        end

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
    end

    sig { params(ecosystem: T.nilable(Ecosystem)).void }
    def record_ecosystem_meta(ecosystem)
      return unless Dependabot::Experiments.enabled?(:enable_record_ecosystem_meta)

      return if ecosystem.nil?

      begin
        ::Dependabot::OpenTelemetry.tracer.in_span("record_ecosystem_meta", kind: :internal) do |_span|
          api_url = "#{base_url}/update_jobs/#{job_id}/record_ecosystem_meta"

          body = {
            data: [
              {
                ecosystem: {
                  name: ecosystem.name,
                  package_manager: version_manager_json(ecosystem.package_manager),
                  language: version_manager_json(ecosystem.language)
                }
              }
            ]
          }

          retry_count = 0

          begin
            response = http_client.post(api_url, json: body)
            raise ApiError, response.body if response.code >= 400
          rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError, ApiError => e
            retry_count += 1
            if retry_count <= MAX_REQUEST_RETRIES
              sleep(rand(3.0..10.0))
              retry
            else
              Dependabot.logger.error(
                "Failed to record ecosystem meta after #{MAX_REQUEST_RETRIES} retries: #{e.message}"
              )
            end
          end
        end
      rescue StandardError => e
        Dependabot.logger.error("Failed to record ecosystem meta: #{e.message}")
      end
    end

    private

    # Update return type to allow returning a Hash or nil
    sig do
      params(version_manager: T.nilable(Dependabot::Ecosystem::VersionManager))
        .returns(T.nilable(T::Hash[String, T.untyped]))
    end
    def version_manager_json(version_manager)
      return nil unless version_manager

      version = version_manager.version_to_s
      raw_version = version_manager.version_to_raw_s

      {
        name: version_manager.name,
        version: version.empty? ? "N/A" : version,
        raw_version: raw_version.empty? ? "N/A" : raw_version,
        requirement: version_manager_requirement_json(version_manager)
      }
    end

    # Update return type to allow returning a Hash or nil
    sig do
      params(version_manager: Dependabot::Ecosystem::VersionManager)
        .returns(T.nilable(T::Hash[String, T.untyped]))
    end
    def version_manager_requirement_json(version_manager)
      requirement = version_manager.requirement
      return nil unless requirement

      {
        raw_constraint: requirement.constraints.join(", "),
        min_raw_version: requirement.min_version&.to_semver.to_s,
        min_version: requirement.min_version&.to_s,
        max_raw_version: requirement.max_version&.to_semver.to_s,
        max_version: requirement.max_version&.to_s
      }
    end

    sig { returns(String) }
    attr_reader :base_url

    sig { returns(T.any(String, Integer)) }
    attr_reader :job_id

    sig { returns(String) }
    attr_reader :job_token

    sig { returns(T.untyped) }
    def http_client
      client = HTTP::Client.new.auth(job_token)
      proxy = ENV["HTTPS_PROXY"] ? URI(T.must(ENV["HTTPS_PROXY"])) : URI(base_url).find_proxy
      unless proxy.nil?
        args = T.unsafe([proxy.host, proxy.port, proxy.user, proxy.password].compact)
        client = client.via(*args)
      end
      client
    end

    sig { params(dependency_change: Dependabot::DependencyChange).returns(T::Hash[String, T.untyped]) }
    def dependency_group_hash(dependency_change)
      return {} unless dependency_change.grouped_update?

      # FIXME: We currently assumpt that _an attempt_ to send a DependencyGroup#id should
      # result in the `grouped-update` flag being set, regardless of whether the
      # DependencyGroup actually exists.
      { "dependency-group": dependency_change.dependency_group.to_h }.compact
    end

    sig do
      params(dependency_change: Dependabot::DependencyChange,
             base_commit_sha: String).returns(T::Hash[String, T.untyped])
    end
    def create_pull_request_data(dependency_change, base_commit_sha)
      data = {
        dependencies: dependency_change.updated_dependencies.map do |dep|
          {
            name: dep.name,
            "previous-version": dep.previous_version,
            requirements: dep.requirements,
            "previous-requirements": dep.previous_requirements,
            directory: dep.directory
          }.merge({
            version: dep.version,
            removed: dep.removed? ? true : nil
          }.compact)
        end,
        "updated-dependency-files": dependency_change.updated_dependency_files_hash,
        "base-commit-sha": base_commit_sha
      }.merge(dependency_group_hash(dependency_change))

      data["commit-message"] = dependency_change.pr_message.commit_message
      data["pr-title"] = dependency_change.pr_message.pr_name
      data["pr-body"] = dependency_change.pr_message.pr_message
      data
    end

    sig { params(response: String).returns(T::Boolean) }
    def dependency_file_not_supported_error?(response)
      body = JSON.parse(response)

      return false unless body.is_a?(Hash)
      return false unless body["errors"]

      INVALID_REQUEST_MSG.match? body["errors"].first["detail"]
    end
  end
end
