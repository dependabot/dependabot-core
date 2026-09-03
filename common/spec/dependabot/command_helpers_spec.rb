# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/command_helpers"
require "rbconfig"
require "tmpdir"

RSpec.describe Dependabot::CommandHelpers do
  describe ".capture3_with_timeout" do
    let(:success_cmd) { command_fixture("success.sh") }
    let(:error_cmd) { command_fixture("error.sh") }
    let(:output_hang_cmd) { command_fixture("output_hang.sh") }
    let(:error_hang_cmd) { command_fixture("error_hang.sh") }
    let(:invalid_cmd) { "non_existent_command" }
    let(:no_timeout_cmd) { command_fixture("no_timeout.sh") }
    let(:timeout) { 1 } # Timeout for hanging commands

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

      it "passes environment, stdin, and spawn options to an argument vector" do
        options = { chdir: Dir.tmpdir }
        command = [
          { "PREFIX" => "prefix:" },
          [RbConfig.ruby, RbConfig.ruby],
          "-e",
          "print ENV.fetch('PREFIX'); print STDIN.read; print ':'; print Dir.pwd",
          options
        ]

        stdout, stderr, status, = described_class.capture3_with_timeout(
          command,
          stdin_data: "input"
        )

        expect(stdout).to eq("prefix:input:#{Dir.tmpdir}")
        expect(stderr).to eq("")
        expect(status).to be_success
        expect(options).to eq(chdir: Dir.tmpdir)
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

        expect(stdout).to eq("This is a output for command error command.\n")
        expect(stderr).to include("This is an error message.")
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

    context "when timeout is zero or negative" do
      it "waiting commands to be done" do
        stdout, stderr, status, elapsed_time = described_class.capture3_with_timeout(
          [no_timeout_cmd],
          timeout: -1
        )

        expect(stdout).to eq("This is a command result.\n")
        expect(stderr).to eql("")
        expect(status).to be_success
        expect(elapsed_time).to be_positive
        expect(elapsed_time).to be < 1
      end
    end

    context "when output_observer requests graceful stop" do
      before do
        stub_const("Dependabot::CommandHelpers::TIMEOUTS::GRACEFULLY_STOP", 1)
      end

      it "terminates early due to observer and logs the reason" do
        # Bash script that prints a trigger then sleeps
        cmd = ["bash", "-c", "echo TRIGGER && sleep 10"]

        observer = proc do |data|
          { gracefully_stop: true, reason: "Observer triggered stop" } if data.include?("TRIGGER")
        end

        stdout, _, status, elapsed_time = described_class.capture3_with_timeout(
          cmd,
          timeout: 100,
          output_observer: observer
        )

        expect(stdout).to include("TRIGGER")
        expect(status).not_to be_nil
        expect(status.exitstatus).to eq(0).or eq(124) # depending on whether it's handled as graceful or timeout
        expect(elapsed_time).to be < 2 # confirms early termination
      end
    end

    context "when logging subprocess lifecycle" do
      let(:logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }

      before do
        allow(Dependabot).to receive(:logger).and_return(logger)
      end

      it "logs git config commands at debug level" do
        described_class.capture3_with_timeout(
          ["git config --global --list"],
          timeout: timeout
        )

        expect(logger).to have_received(:debug).with(a_string_including("Started process PID"))
        expect(logger).to have_received(:debug).with(a_string_including("Process PID"))
        expect(logger).to have_received(:debug).with(a_string_including("Total execution time"))
      end

      it "logs direct-exec git config commands at debug level" do
        described_class.capture3_with_timeout(
          [%w(git git), "config", "--global", "--list"],
          timeout: timeout
        )

        expect(logger).to have_received(:debug)
          .with(a_string_including("command: git config --global --list"))
      end

      it "logs non-git-config commands at info level" do
        described_class.capture3_with_timeout(
          [success_cmd],
          timeout: timeout
        )

        expect(logger).to have_received(:info).with(a_string_including("Started process PID"))
        expect(logger).to have_received(:info).with(a_string_including("Process PID"))
        expect(logger).to have_received(:info).with(a_string_including("Total execution time"))
      end
    end

    context "when the wait thread reports no process status (child reaped externally)" do
      let(:logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }

      let(:process_with_nil_status) do
        process_io = IO.popen(["true"], "r+")
        stderr_io, stderr_writer = IO.pipe
        stderr_writer.close
        wait_thr = instance_double(Process::Waiter, pid: process_io.pid, value: nil, join: nil)

        [process_io, stderr_io, wait_thr]
      end

      before do
        allow(Dependabot).to receive(:logger).and_return(logger)

        # Simulates `terminate_process` reaping the child before the wait thread reads its status.
        allow(described_class).to receive(:open_process).and_return(process_with_nil_status)
      end

      it "does not raise and returns a nil-safe status" do
        stdout, stderr, status, elapsed_time = described_class.capture3_with_timeout(
          ["some-command"],
          timeout: timeout
        )

        expect(stdout).to eq("")
        expect(stderr).to eq("")
        expect(status).not_to be_nil
        expect(status.exitstatus).to eq(0)
        expect(status.success?).to be(false)
        expect(status.pid).to be_nil
        expect(status.termsig).to be_nil
        expect(status.to_s).to eq("unknown status")
        expect(elapsed_time).to be >= 0
      end
    end
  end
end
