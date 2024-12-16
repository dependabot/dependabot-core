# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/command_helpers"

RSpec.describe Dependabot::CommandHelpers do
  describe ".capture3_with_timeout" do
    let(:success_cmd) { command_fixture("success.sh") }
    let(:error_cmd) { command_fixture("error.sh") }
    let(:output_hang_cmd) { command_fixture("output_hang.sh") }
    let(:error_hang_cmd) { command_fixture("error_hang.sh") }
    let(:invalid_cmd) { "non_existent_command" }
    let(:timeout) { 2 } # Timeout for hanging commands

    context "when the command runs successfully" do
      it "captures stdout and exits successfully" do
        stdout, stderr, status, elapsed_time = described_class.capture3_with_timeout(
          [success_cmd],
          timeout: timeout
        )

        expect(stdout).to eq("This is a successful command.\n")
        expect(stderr).to eq("")
        expect(status.exitstatus).to eq(0)
        expect(elapsed_time).to be > 0
      end
    end

    context "when the command runs with an error" do
      it "captures stderr and returns an error status" do
        stdout, stderr, status, elapsed_time = described_class.capture3_with_timeout(
          [error_cmd],
          timeout: timeout
        )

        expect(stdout).to eq("")
        expect(stderr).to eq("This is an error message.\n")
        expect(status.exitstatus).to eq(1)
        expect(elapsed_time).to be > 0
      end
    end

    context "when the command runs with output but hangs" do
      it "times out and appends a timeout message to stderr" do
        stdout, stderr, status, elapsed_time = described_class.capture3_with_timeout(
          [output_hang_cmd],
          timeout: timeout
        )

        expect(stdout).to eq("This is a hanging command.\n")
        expect(stderr).to include("Timed out due to inactivity after #{timeout} seconds")
        expect(status.exitstatus).to eq(124) # Timeout-specific status code
        expect(elapsed_time).to be_within(1).of(timeout)
      end
    end

    context "when the command runs with an error but hangs" do
      it "times out and appends a timeout message to stderr" do
        stdout, stderr, status, elapsed_time = described_class.capture3_with_timeout(
          [error_hang_cmd],
          timeout: timeout
        )

        expect(stdout).to eq("")
        expect(stderr).to include("This is a hanging error command.")
        expect(stderr).to include("Timed out due to inactivity after #{timeout} seconds")
        expect(status.exitstatus).to eq(124)
        expect(elapsed_time).to be_within(1).of(timeout)
      end
    end

    context "when the command is invalid" do
      it "raises an error and captures stderr" do
        stdout, stderr, status, elapsed_time = described_class.capture3_with_timeout(
          [invalid_cmd],
          timeout: timeout
        )

        expect(stdout).to eq("")
        expect(stderr).to include("No such file or directory - non_existent_command") if stderr
        expect(status).to be_nil
        expect(elapsed_time).to be > 0
      end
    end
  end
end
