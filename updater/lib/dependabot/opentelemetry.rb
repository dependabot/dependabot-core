# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

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
      ENV['OTEL_TRACES_EXPORTER'] ||= 'console'
      require "opentelemetry/sdk"
      require "opentelemetry/exporter/otlp"
      require "opentelemetry/instrumentation/excon"
      require "opentelemetry/instrumentation/faraday"
      require "opentelemetry/instrumentation/http"

      ::OpenTelemetry::SDK.configure do |config|
        config.service_name = "dependabot"
        config.use "OpenTelemetry::Instrumentation::Excon"
        config.use "OpenTelemetry::Instrumentation::Faraday"
        config.use "OpenTelemetry::Instrumentation::Http"
        c.add_span_processor(
              ::OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
                ::OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
              )
            )
      end
    end


    sig { params(job_id: T.any(String, Integer), error_type: T.any(String, Symbol), error_details: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def record_update_job_error(job_id:, error_type:, error_details:)
      return unless should_configure?

      current_span = ::OpenTelemetry::Trace.current_span

      current_span.add_event(error_type, attributes: {
        "dependabot.job.Id" => job_id,
        "dependabot.job.error_type" => error_type,
        "dependabot.job.error_details" => error_details
      })
    end

    sig { params(
      error: StandardError,
      job: T.untyped,
      tags: T::Hash[String, T.untyped],).void }
    def record_exception(error: StandardError, job: nil, tags: {})
      return unless should_configure?

      current_span = ::OpenTelemetry::Trace.current_span

      current_span.set_attribute("dependabot.job.id", job&.id) if job
      current_span.add_attributes(tags) if tags.any?

      current_span.status = ::OpenTelemetry::Trace::Status.error(e.message)
      current_span.record_exception(e)
    end
  end
end
