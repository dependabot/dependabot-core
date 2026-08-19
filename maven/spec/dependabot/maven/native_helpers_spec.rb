# typed: strong
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"
require "spec_helper"
require "dependabot/maven/native_helpers"

RSpec.describe Dependabot::Maven::NativeHelpers do
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
  end
end
