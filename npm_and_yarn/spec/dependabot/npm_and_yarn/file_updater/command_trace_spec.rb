# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/file_updater/command_trace"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::CommandTrace do
  let(:traces) { [] }

  describe ".record" do
    it "records a successful command and returns the block result" do
      result = described_class.record(
        traces: traces,
        package_manager: "npm",
        command: "install --package-lock-only",
        fingerprint: "install --package-lock-only"
      ) do
        "ok-stdout"
      end

      expect(result).to eq("ok-stdout")
      expect(traces.length).to eq(1)

      trace = traces.first
      expect(trace.package_manager).to eq("npm")
      expect(trace.command).to eq("install --package-lock-only")
      expect(trace.fingerprint).to eq("install --package-lock-only")
      expect(trace.success).to be(true)
      expect(trace.stdout).to eq("ok-stdout")
      expect(trace.stderr).to be_nil
      expect(trace.error_class).to be_nil
      expect(trace.duration_ms).to be >= 0
    end

    it "appends the trace before the block runs (visible on raise)" do
      expect do
        described_class.record(
          traces: traces,
          package_manager: "npm",
          command: "explode"
        ) do
          raise StandardError, "boom"
        end
      end.to raise_error(StandardError, "boom")

      expect(traces.length).to eq(1)
      trace = traces.first
      expect(trace.success).to be(false)
      expect(trace.error_class).to eq("StandardError")
      expect(trace.error_message).to eq("boom")
    end

    it "captures stderr from a HelperSubprocessFailed failure" do
      err = Dependabot::SharedHelpers::HelperSubprocessFailed.new(
        message: "subprocess error",
        error_context: { stderr_output: "the stderr details" }
      )

      expect do
        described_class.record(
          traces: traces,
          package_manager: "pnpm",
          command: "install --lockfile-only"
        ) do
          raise err
        end
      end.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)

      trace = traces.first
      expect(trace.success).to be(false)
      expect(trace.error_class).to eq("Dependabot::SharedHelpers::HelperSubprocessFailed")
      expect(trace.stderr).to eq("the stderr details")
    end

    it "truncates oversized stdout, stderr, and error messages" do
      big_stdout = "x" * (described_class::STDOUT_LIMIT + 500)
      result = described_class.record(
        traces: traces,
        package_manager: "yarn",
        command: "install"
      ) { big_stdout }

      expect(result).to eq(big_stdout)
      trace = traces.first
      expect(trace.stdout.length).to be < big_stdout.length
      expect(trace.stdout).to include("truncated 500 chars")
    end

    it "leaves stdout nil when the block returns a non-string value" do
      described_class.record(
        traces: traces,
        package_manager: "yarn",
        command: "noop"
      ) { 42 }

      expect(traces.first.stdout).to be_nil
      expect(traces.first.success).to be(true)
    end
  end

  describe "#to_h" do
    it "drops nil-valued fields" do
      described_class.record(
        traces: traces,
        package_manager: "npm",
        command: "install"
      ) { "out" }

      hash = traces.first.to_h
      expect(hash.keys).to include(:package_manager, :command, :duration_ms, :success, :stdout)
      expect(hash.keys).not_to include(:error_class, :error_message, :stderr, :content_changed_after)
    end

    it "includes content_changed_after when set" do
      described_class.record(
        traces: traces,
        package_manager: "npm",
        command: "install"
      ) { "out" }
      traces.first.content_changed_after = false

      expect(traces.first.to_h[:content_changed_after]).to be(false)
    end
  end

  describe "#summary_line" do
    it "produces a one-line summary that includes status and content_changed marker" do
      described_class.record(
        traces: traces,
        package_manager: "npm",
        command: "install --package-lock-only"
      ) { "out" }
      traces.first.content_changed_after = false

      line = traces.first.summary_line
      expect(line).to include("[npm]")
      expect(line).to include("status=ok")
      expect(line).to include("content_changed=false")
    end

    it "uses '?' when content_changed_after has not been set" do
      described_class.record(
        traces: traces,
        package_manager: "yarn",
        command: "install"
      ) { "out" }

      expect(traces.first.summary_line).to include("content_changed=?")
    end
  end
end
