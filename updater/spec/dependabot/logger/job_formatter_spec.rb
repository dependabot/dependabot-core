# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/logger/formats"

RSpec.describe Dependabot::Logger::JobFormatter do
  describe "#new" do
    it "returns a formatter when provided a job_id" do
      formatter = described_class.new("job_id")
      expect(formatter).to be_a(described_class)
    end

    it "returns a formatter when provided a nil job_id" do
      formatter = described_class.new(nil)
      expect(formatter).to be_a(described_class)
    end
  end

  describe "#call" do
    let(:job_id) { "job_id" }
    let(:formatter) { described_class.new(job_id) }

    it "returns a formatted log line with a job_id" do
      log_line = formatter.call("INFO", Time.now, "progname", "msg")

      expect(log_line).to match(%r{\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} INFO <job_job_id> msg\n})
    end

    it "returns a formatted log line with a nil job_id" do
      formatter = described_class.new(nil)
      log_line = formatter.call("INFO", Time.now, "progname", "msg")

      expect(log_line).to match(%r{\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} INFO <job_unknown_id> msg\n})
    end

    it "returns a formatted log line with only a severity" do
      log_line = formatter.call("ERROR", nil, nil, nil)

      expect(log_line).to match(%r{\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2} ERROR <job_job_id> nil\n})
    end

    it "returns a formatted log line when using the CLI" do
      formatter = described_class.new("cli")
      log_line = formatter.call("ERROR", nil, nil, nil)

      expect(log_line).to match(%r{\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2} ERROR nil\n})
    end
  end
end
