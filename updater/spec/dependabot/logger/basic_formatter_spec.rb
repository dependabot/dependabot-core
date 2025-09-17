# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/logger/formats"

RSpec.describe Dependabot::Logger::BasicFormatter do
  describe "#call" do
    it "returns a formatted log line" do
      formatter = described_class.new
      log_line = formatter.call("INFO", Time.now, "progname", "msg")

      expect(log_line).to match(%r{\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} INFO msg\n})
    end

    it "returns a formatted log line with only a severity" do
      formatter = described_class.new
      log_line = formatter.call("ERROR", nil, nil, nil)

      expect(log_line).to match(%r{\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2} ERROR nil\n})
    end
  end
end
