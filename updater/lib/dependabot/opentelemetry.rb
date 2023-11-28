# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "opentelemetry/sdk"

module Dependabot
  module OpenTelemetry
    extend T::Sig

    sig { returns(T::Boolean) }
    def self.should_configure?
      ENV["OTEL_ENABLED"] == "true"
    end

    sig { void }
    def self.configure
      return unless should_configure?
      # Export traces to console by default
      require "opentelemetry/exporter/otlp"
      require "opentelemetry/instrumentation/excon"
      require "opentelemetry/instrumentation/faraday"
      require "opentelemetry/instrumentation/http"
      ENV['OTEL_TRACES_EXPORTER'] ||= 'console'

      ::OpenTelemetry::SDK.configure do |config|
        config.service_name = "dependabot"
        config.add_span_processor(
              ::OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
                ::OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
              )
            )
        config.use "OpenTelemetry::Instrumentation::Excon"
        config.use "OpenTelemetry::Instrumentation::Faraday"
        config.use "OpenTelemetry::Instrumentation::Http"
      end

      tracer
    end

    sig { returns(T.nilable(::OpenTelemetry::Trace::Tracer)) }
    def self.tracer
      return unless should_configure?
      return ::OpenTelemetry.tracer_provider.tracer('dependabot')
    end


    sig { params(job_id: T.any(String, Integer), error_type: T.any(String, Symbol), error_details: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def self.record_update_job_error(job_id:, error_type:, error_details:)
      return unless should_configure?

      current_span = ::OpenTelemetry::Trace.current_span

      attributes = {
        "dependabot.job.id" => job_id,
        "dependabot.job.error_type" => error_type,
      }

      error_details.each do |key, value|
        attributes.store("dependabot.job.error_details.#{key}", value)
      end

      current_span.add_event(error_type, attributes: attributes)
    end

    sig do
      params(
      error: StandardError,
      job: T.untyped,
      tags: T::Hash[String, T.untyped]).void
    end
    def self.record_exception(error: StandardError, job: nil, tags: {})
      return unless should_configure?

      current_span = ::OpenTelemetry::Trace.current_span

      current_span.set_attribute("dependabot.job.id", job&.id) if job
      current_span.add_attributes(tags) if tags.any?

      current_span.status = ::OpenTelemetry::Trace::Status.error(error.message)
      current_span.record_exception(error)
    end
  end
end
