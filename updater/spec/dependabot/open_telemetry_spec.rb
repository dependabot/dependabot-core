# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/opentelemetry"

RSpec.describe Dependabot::OpenTelemetry do
  let(:span) { instance_double(OpenTelemetry::Trace::Span) }

  before do
    allow(OpenTelemetry::Trace).to receive(:current_span).and_return(span)
  end

  describe ".record_update_job_error" do
    it "records hash details as individual attributes" do
      expect(span).to receive(:add_event).with(
        "update_error",
        attributes: {
          "dependabot.job.id" => "123",
          "dependabot.job.error_type" => "update_error",
          "dependabot.job.error_details.package-manager" => "bundler"
        }
      )

      described_class.record_update_job_error(
        job_id: "123",
        error_type: "update_error",
        error_details: { "package-manager": "bundler" }
      )
    end

    it "records string details under the base detail attribute" do
      expect(span).to receive(:add_event).with(
        :update_error,
        attributes: {
          "dependabot.job.id" => 123,
          "dependabot.job.error_type" => :update_error,
          "dependabot.job.error_details" => "details"
        }
      )

      described_class.record_update_job_error(
        job_id: 123,
        error_type: :update_error,
        error_details: "details"
      )
    end

    it "omits nil details" do
      expect(span).to receive(:add_event).with(
        "update_error",
        attributes: {
          "dependabot.job.id" => "123",
          "dependabot.job.error_type" => "update_error"
        }
      )

      described_class.record_update_job_error(
        job_id: "123",
        error_type: "update_error",
        error_details: nil
      )
    end
  end

  describe ".record_exception" do
    let(:error) { StandardError.new("boom") }
    let(:job) { instance_double(Dependabot::Job, id: "123") }

    it "records the job, tags, status, and exception" do
      expect(span).to receive(:set_attribute).with("dependabot.job.id", "123")
      expect(span).to receive(:add_attributes).with({ "package-manager" => "bundler" })
      expect(span).to receive(:status=).with(instance_of(OpenTelemetry::Trace::Status))
      expect(span).to receive(:record_exception).with(error)

      described_class.record_exception(
        error: error,
        job: job,
        tags: { "package-manager" => "bundler" }
      )
    end
  end
end
