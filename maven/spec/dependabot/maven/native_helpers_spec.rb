# typed: strong
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"
require "spec_helper"
require "dependabot/maven/native_helpers"

RSpec.describe Dependabot::Maven::NativeHelpers do
  def wrapper_failure(output)
    Dependabot::SharedHelpers::HelperSubprocessFailed.new(
      message: output,
      error_context: { command: "mvn ..." }
    )
  end

  def capture_wrapper_error(output)
    described_class.handle_wrapper_error(wrapper_failure(output))
    nil
  rescue Dependabot::DependabotError => e
    e
  end

  describe "handle_tool_error" do
    context "when the output contains a 403 error" do
      let(:output) { "Could not transfer artifact com.example:example:jar:1.0.0 from/to example-repo (https://example.com/repo): status code: 403" }

      it "raises PrivateSourceAuthenticationFailure for 401 and 403 errors" do
        expect do
          described_class.handle_tool_error(output)
        end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "when the output contains a 401 error" do
      let(:output) { "Could not transfer artifact com.example:example:jar:1.0.0 from/to example-repo (https://example.com/repo): status code: 401" }

      it "raises PrivateSourceAuthenticationFailure for 401 and 403 errors" do
        expect do
          described_class.handle_tool_error(output)
        end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    it "raises DependabotError for other errors" do
      output = "Some other error occurred"
      expect do
        described_class.handle_tool_error(output)
      end.to raise_error(Dependabot::DependabotError)
    end
  end

  describe "handle_wrapper_error" do
    it "raises PrivateSourceAuthenticationFailure on a 401 transfer failure" do
      output = "[ERROR] Could not transfer artifact org.apache.maven:apache-maven:zip:3.9.9 " \
               "from/to central (https://repo.example.com/maven): status code: 401"
      expect do
        described_class.handle_wrapper_error(wrapper_failure(output))
      end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure, /repo\.example\.com/)
    end

    it "raises PrivateSourceAuthenticationFailure on a 403 transfer failure" do
      output = "[ERROR] Could not transfer artifact org.apache.maven:apache-maven:zip:3.9.9 " \
               "from/to central (https://repo.example.com/maven): status code: 403"
      expect do
        described_class.handle_wrapper_error(wrapper_failure(output))
      end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
    end

    it "raises DependencyFileNotResolvable when the wrapper plugin cannot be resolved" do
      output = <<~OUTPUT
        [INFO] Scanning for projects...
        [ERROR] Plugin org.apache.maven.plugins:maven-wrapper-plugin:3.3.4 or one of its dependencies could not be resolved: The following artifacts could not be resolved: org.apache.maven.plugins:maven-wrapper-plugin:pom:3.3.4 (absent)
        [ERROR] -> [Help 1]
      OUTPUT
      expect do
        described_class.handle_wrapper_error(wrapper_failure(output))
      end.to raise_error(Dependabot::DependencyFileNotResolvable, /Maven Wrapper plugin/)
    end

    it "raises MisconfiguredTooling surfacing the Maven error for unclassified failures" do
      output = <<~OUTPUT
        [INFO] Scanning for projects...
        [ERROR] Failed to execute goal on project demo: proxy host could not be reached
        [ERROR] -> [Help 1]
      OUTPUT
      error = capture_wrapper_error(output)
      expect(error).to be_a(Dependabot::MisconfiguredTooling)
      expect(error.tool_name).to eq("Maven Wrapper")
      expect(error.tool_message).to include("proxy host could not be reached")
      # Only the [ERROR] lines are surfaced, not the [INFO] noise.
      expect(error.tool_message).not_to include("Scanning for projects")
    end

    it "re-raises the original HelperSubprocessFailed when there are no [ERROR] lines" do
      # Inactivity timeouts and a missing `mvn` executable surface as
      # HelperSubprocessFailed without Maven `[ERROR]` markers. These are not tooling
      # misconfigurations, so the original error is re-raised for normal unknown-error
      # routing rather than serialized as MisconfiguredTooling.
      output = "some unexpected failure without maven error markers"
      expect do
        described_class.handle_wrapper_error(wrapper_failure(output))
      end.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /some unexpected failure/)
    end

    it "truncates an overly long error summary" do
      output = "[ERROR] #{'x' * 5_000}"
      error = capture_wrapper_error(output)
      expect(error).to be_a(Dependabot::MisconfiguredTooling)
      expect(error.tool_message.length).to be <= 2_003 # 2000 chars + "..."
      expect(error.tool_message).to end_with("...")
    end
  end

  describe "run_mvnw_wrapper" do
    let(:env) { { "SOME_VAR" => "value" } }

    it "passes an argument vector (not a pre-escaped shell string) to run_shell_command" do
      expect(Dependabot::SharedHelpers).to receive(:run_shell_command) do |cmd, **_kwargs|
        expect(cmd).to be_an(Array)
        expect(cmd).to eq(
          [
            "mvn",
            "org.apache.maven.plugins:maven-wrapper-plugin:3.3.4:wrapper",
            "-Dmaven=3.6.3",
            "-Dtype=only-script",
            "--no-transfer-progress"
          ]
        )
        # No shell escaping should leak into the arguments.
        expect(cmd.join(" ")).not_to include("\\")
        ""
      end

      described_class.run_mvnw_wrapper(
        version: "3.6.3",
        wrapper_plugin_version: "3.3.4",
        env: env,
        distribution_type: "only-script"
      )
    end

    it "appends extra_args and forwards a non-'.' cwd" do
      expect(Dependabot::SharedHelpers).to receive(:run_shell_command) do |cmd, **kwargs|
        expect(cmd.last).to eq("-DdistributionUrl=https://example.com/apache-maven-3.6.3-bin.zip")
        expect(kwargs[:cwd]).to eq("subdir")
        expect(kwargs[:env]).to eq(env)
        ""
      end

      described_class.run_mvnw_wrapper(
        version: "3.6.3",
        wrapper_plugin_version: "3.3.4",
        env: env,
        distribution_type: "bin",
        extra_args: ["-DdistributionUrl=https://example.com/apache-maven-3.6.3-bin.zip"],
        cwd: "subdir"
      )
    end

    it "passes cwd as nil when cwd is '.'" do
      expect(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_cmd, **kwargs|
        expect(kwargs[:cwd]).to be_nil
        ""
      end

      described_class.run_mvnw_wrapper(
        version: "3.6.3",
        wrapper_plugin_version: "3.3.4",
        env: env,
        distribution_type: "bin",
        cwd: "."
      )
    end

    context "when the subprocess fails" do
      let(:mvn_output) do
        "[ERROR] Plugin org.apache.maven.plugins:maven-wrapper-plugin:3.3.4 or one of its " \
          "dependencies could not be resolved: absent"
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: mvn_output,
            error_context: { command: "mvn ..." }
          )
        )
      end

      it "logs the full Maven output before re-raising" do
        expect(Dependabot.logger).to receive(:warn).with(a_string_including(mvn_output))

        expect do
          described_class.run_mvnw_wrapper(
            version: "3.6.3",
            wrapper_plugin_version: "3.3.4",
            env: env,
            distribution_type: "only-script"
          )
        end.to raise_error(Dependabot::DependencyFileNotResolvable)
      end

      it "re-raises a classified Dependabot error, not the raw HelperSubprocessFailed" do
        # DependencyFileNotResolvable is not a HelperSubprocessFailed, so the updater
        # will surface an actionable error type rather than an opaque SubprocessFailed.
        expect do
          described_class.run_mvnw_wrapper(
            version: "3.6.3",
            wrapper_plugin_version: "3.3.4",
            env: env,
            distribution_type: "only-script"
          )
        end.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end
end
