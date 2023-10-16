# typed: false
# frozen_string_literal: true

module Dependabot
  module OpenTelemetry
    def self.should_configure?
      ENV["OTEL_ENABLED"] == "true"
    end

    def self.configure
      return unless should_configure?

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
      end
    end
  end
end
