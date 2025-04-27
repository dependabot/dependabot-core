# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "opentelemetry/sdk"
require "opentelemetry-logs-sdk"
require "opentelemetry-metrics-sdk"

module Dependabot
  module OpenTelemetry
    extend T::Sig

    module Attributes
      JOB_ID = "dependabot.job.id"
      WARN_TYPE = "dependabot.job.warn_type"
      WARN_TITLE = "dependabot.job.warn_title"
      WARN_DESCRIPTION = "dependabot.job.warn_description"
      ERROR_TYPE = "dependabot.job.error_type"
      ERROR_DETAILS = "dependabot.job.error_details"
      METRIC = "dependabot.metric"
      BASE_COMMIT_SHA = "dependabot.base_commit_sha"
      DEPENDENCY_NAMES = "dependabot.dependency_names"
      PR_CLOSE_REASON = "dependabot.pr_close_reason"
    end

    sig { returns(T::Boolean) }
    def self.should_configure?
      ENV["OTEL_ENABLED"] == "true"
    end

    sig { void }
    def self.configure
      return unless should_configure?

      puts "OpenTelemetry is enabled, configuring..."

      require "opentelemetry/exporter/otlp"
      require "opentelemetry/exporter/otlp_logs"
      require "opentelemetry/exporter/otlp_metrics"

      # OpenTelemetry instrumentation expects the related gem to be loaded.
      # While most are already loaded by this point in initialization, some are not.
      # We explicitly load them here to ensure that the instrumentation is enabled.
      require "excon"
      require "opentelemetry/instrumentation/excon"
      require "faraday"
      require "opentelemetry/instrumentation/faraday"
      require "http"
      require "opentelemetry/instrumentation/http"
      require "net/http"
      require "opentelemetry/instrumentation/net/http"

      ::OpenTelemetry::SDK.configure do |config|
        config.service_name = "dependabot"
        config.use "OpenTelemetry::Instrumentation::Excon"
        config.use "OpenTelemetry::Instrumentation::Faraday"
        config.use "OpenTelemetry::Instrumentation::HTTP"
        config.use "OpenTelemetry::Instrumentation::Net::HTTP"
      end

      tracer
    end

    sig { returns(::OpenTelemetry::Trace::Tracer) }
    def self.tracer
      ::OpenTelemetry.tracer_provider.tracer("dependabot", Dependabot::VERSION)
    end

    sig { void }
    def self.shutdown
      return unless should_configure?

      ::OpenTelemetry.tracer_provider.force_flush
      ::OpenTelemetry.tracer_provider.shutdown
    end

    sig do
      params(
        job_id: T.any(String, Integer),
        error_type: T.any(String, Symbol),
        error_details: T.nilable(T::Hash[T.untyped, T.untyped])
      ).void
    end
    def self.record_update_job_error(job_id:, error_type:, error_details:)
      current_span = ::OpenTelemetry::Trace.current_span

      attributes = {
        Attributes::JOB_ID => job_id,
        Attributes::ERROR_TYPE => error_type
      }

      error_details&.each do |key, value|
        attributes.store("#{Attributes::ERROR_DETAILS}.#{key}", value)
      end

      current_span.add_event(error_type, attributes: attributes)
    end

    sig do
      params(
        job_id: T.any(String, Integer),
        warn_type: T.any(String, Symbol),
        warn_title: String,
        warn_description: String
      ).void
    end
    def self.record_update_job_warning(job_id:, warn_type:, warn_title:, warn_description:)
      current_span = ::OpenTelemetry::Trace.current_span

      attributes = {
        Attributes::JOB_ID => job_id,
        Attributes::WARN_TYPE => warn_type,
        Attributes::WARN_TITLE => warn_title,
        Attributes::WARN_DESCRIPTION => warn_description
      }
      current_span.add_event(warn_type, attributes: attributes)
    end

    sig do
      params(
        error: StandardError,
        job: T.untyped,
        tags: T::Hash[String, T.untyped]
      ).void
    end
    def self.record_exception(error:, job: nil, tags: {})
      current_span = ::OpenTelemetry::Trace.current_span

      current_span.set_attribute(Attributes::JOB_ID, job.id.to_s) if job
      current_span.add_attributes(tags) if tags.any?

      current_span.status = ::OpenTelemetry::Trace::Status.error(error.message)
      current_span.record_exception(error)
    end
  end
end
