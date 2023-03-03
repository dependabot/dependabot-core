# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget/native_helpers"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Nuget::NativeHelpers do
  let(:dependabot_home) { ENV.fetch("DEPENDABOT_HOME", nil) || Dir.home }

  describe "nuget updater command" do
    subject(:command) do
      (command,) = described_class.get_nuget_updater_tool_command(job_path: job_path,
                                                                  repo_root: repo_root,
                                                                  proj_path: proj_path,
                                                                  dependency: dependency,
                                                                  is_transitive: is_transitive,
                                                                  result_output_path: result_output_path)
      command = command.gsub(/^.*NuGetUpdater.Cli/, "/path/to/NuGetUpdater.Cli") # normalize path for unit test
      command
    end

    let(:job_path) { "/path/to/job.json" }
    let(:repo_root) { "/path/to/repo" }
    let(:proj_path) { "/path/to/repo/src/some project/some_project.csproj" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "Some.Package",
        version: "1.2.3",
        previous_version: "1.2.2",
        requirements: [{ file: "some_project.csproj", requirement: "1.2.3", groups: [], source: nil }],
        previous_requirements: [{ file: "some_project.csproj", requirement: "1.2.2", groups: [], source: nil }],
        package_manager: "nuget"
      )
    end
    let(:is_transitive) { false }
    let(:result_output_path) { "/path/to/result.json" }

    before do
      ENV["DEPENDABOT_JOB_ID"] = "TEST-JOB-ID"
    end

    after do
      ENV.delete("DEPENDABOT_JOB_ID")
    end

    it "returns a properly formatted command with spaces on the path" do
      expect(command).to eq("/path/to/NuGetUpdater.Cli update --job-id TEST-JOB-ID --job-path /path/to/job.json " \
                            "--repo-root /path/to/repo " \
                            '--solution-or-project /path/to/repo/src/some\ project/some_project.csproj ' \
                            "--dependency Some.Package --new-version 1.2.3 --previous-version 1.2.2 " \
                            "--result-output-path /path/to/result.json")
    end

    context "when invoking tool with spaces in path, it generates expected warning" do
      # the minimum job object required by the updater
      let(:job) do
        {
          job: {
            "allowed-updates": [
              { "update-type": "all" }
            ],
            "package-manager": "nuget",
            source: {
              provider: "github",
              repo: "gocardless/bump",
              directory: "/",
              branch: "main"
            }
          }
        }
      end

      let(:job_path) { Tempfile.new.path }

      before do
        allow(Dependabot.logger).to receive(:error)
        File.write(job_path, job.to_json)
      end

      after do
        FileUtils.rm_f(job_path)
      end

      it "the tool runs with command line arguments properly interpreted" do
        # This test will fail if the command line arguments weren't properly interpreted
        described_class.run_nuget_updater_tool(job_path: job_path,
                                               repo_root: repo_root,
                                               proj_path: proj_path,
                                               dependency: dependency,
                                               is_transitive: is_transitive,
                                               credentials: [])
        expect(Dependabot.logger).not_to have_received(:error)
      end
    end

    context "with a private source authentication failure" do
      before do
        # write out the result file
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command)
          .and_wrap_original do |_original_method, *_args, &_block|
            result = {
              Error: {
                "error-type": "private_source_authentication_failure",
                "error-details": {
                  source: "some-url"
                }
              }
            }
            File.write(described_class.update_result_file_path, result.to_json)
          end
      end

      it "raises the correct error" do
        expect do
          described_class.run_nuget_updater_tool(job_path: job_path,
                                                 repo_root: repo_root,
                                                 proj_path: proj_path,
                                                 dependency: dependency,
                                                 is_transitive: is_transitive,
                                                 credentials: [])
        end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a missing file" do
      before do
        # write out the result file
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command)
          .and_wrap_original do |_original_method, *_args, &_block|
            result = {
              Error: {
                "error-type": "dependency_file_not_found",
                "error-details": {
                  message: "some message",
                  "file-path": "/some/file"
                }
              }
            }
            File.write(described_class.update_result_file_path, result.to_json)
          end
      end

      it "raises the correct error" do
        expect do
          described_class.run_nuget_updater_tool(job_path: job_path,
                                                 repo_root: repo_root,
                                                 proj_path: proj_path,
                                                 dependency: dependency,
                                                 is_transitive: is_transitive,
                                                 credentials: [])
        end.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end

  describe "#ensure_no_errors" do
    subject(:error_message) do
      described_class.ensure_no_errors(JSON.parse(json))

      # defaults to no error
      return nil
    rescue StandardError => e
      return e
    end

    context "when nothing is reported" do
      let(:json) { "{}" } # an empty object

      it { is_expected.to be_nil }
    end

    context "when the error is expclicitly null" do
      let(:json) do
        {
          Error: nil
        }.to_json
      end

      it { is_expected.to be_nil }
    end

    context "when a dependency file was not found" do
      let(:json) do
        {
          Error: {
            "error-type": "dependency_file_not_found",
            "error-details": {
              message: "some message",
              "file-path": "/some/file"
            }
          }
        }.to_json
      end

      it { is_expected.to be_a Dependabot::DependencyFileNotFound }
    end

    context "when a file is not parseable" do
      let(:json) do
        {
          Error: {
            "error-type": "dependency_file_not_parseable",
            "error-details": {
              message: "some message",
              "file-path": "/some/file"
            }
          }
        }.to_json
      end

      it { is_expected.to be_a Dependabot::DependencyFileNotParseable }
    end

    context "when a requirement cannot be parsed" do
      let(:json) do
        {
          Error: {
            "error-type": "illformed_requirement",
            "error-details": {
              message: "some message"
            }
          }
        }.to_json
      end

      it { is_expected.to be_a Dependabot::BadRequirementError }
    end

    context "when an authenticated feed was rejected" do
      let(:json) do
        {
          Error: {
            "error-type": "private_source_authentication_failure",
            "error-details": {
              source: "some-url"
            }
          }
        }.to_json
      end

      it { is_expected.to be_a Dependabot::PrivateSourceAuthenticationFailure }
    end

    context "when a feed rate limit is reached" do
      let(:json) do
        {
          Error: {
            "error-type": "private_source_bad_response",
            "error-details": {
              source: "some-url"
            }
          }
        }.to_json
      end

      it { is_expected.to be_a Dependabot::PrivateSourceBadResponse }
    end

    context "when an update is not possible" do
      let(:json) do
        {
          Error: {
            "error-type": "update_not_possible",
            "error-details": {
              dependencies: %w(dep1 dep2)
            }
          }
        }.to_json
      end

      it { is_expected.to be_a Dependabot::UpdateNotPossible }
    end

    context "when an unknown error is reported" do
      let(:json) do
        {
          Error: {
            "error-type": "unknown_error",
            "error-details": {
              message: "some message"
            }
          }
        }.to_json
      end

      it { is_expected.to be_a Dependabot::DependabotError }
    end

    context "when any other type of error is returned" do
      let(:json) do
        {
          Error: {
            "error-type": "some_error_type_that_is_not_handled",
            "error-details": {
              message: "some message"
            }
          }
        }.to_json
      end

      it { is_expected.to be_a StandardError }
    end
  end
end
