# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget/native_helpers"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Nuget::NativeHelpers do
  let(:dependabot_home) { ENV.fetch("DEPENDABOT_HOME", nil) || Dir.home }

  describe "nuget updater command" do
    subject(:command) do
      (command,) = described_class.get_nuget_updater_tool_command(repo_root: repo_root,
                                                                  proj_path: proj_path,
                                                                  dependency: dependency,
                                                                  is_transitive: is_transitive,
                                                                  result_output_path: result_output_path)
      command = command.gsub(/^.*NuGetUpdater.Cli/, "/path/to/NuGetUpdater.Cli") # normalize path for unit test
      command
    end

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

    it "returns a properly formatted command with spaces on the path" do
      expect(command).to eq("/path/to/NuGetUpdater.Cli update --repo-root /path/to/repo " \
                            '--solution-or-project /path/to/repo/src/some\ project/some_project.csproj ' \
                            "--dependency Some.Package --new-version 1.2.3 --previous-version 1.2.2 " \
                            "--result-output-path /path/to/result.json")
    end

    context "when invoking tool with spaces in path, it generates expected warning" do
      before do
        allow(Dependabot.logger).to receive(:error)
      end

      it "the tool runs with command line arguments properly interpreted" do
        # This test will fail if the command line arguments weren't properly interpreted
        described_class.run_nuget_updater_tool(repo_root: repo_root,
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
              ErrorType: "AuthenticationFailure",
              ErrorDetails: "the-error-details"
            }
            File.write(described_class.update_result_file_path, result.to_json)
          end
      end

      it "raises the correct error" do
        expect do
          described_class.run_nuget_updater_tool(repo_root: repo_root,
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
              ErrorType: "MissingFile",
              ErrorDetails: "the-error-details"
            }
            File.write(described_class.update_result_file_path, result.to_json)
          end
      end

      it "raises the correct error" do
        expect do
          described_class.run_nuget_updater_tool(repo_root: repo_root,
                                                 proj_path: proj_path,
                                                 dependency: dependency,
                                                 is_transitive: is_transitive,
                                                 credentials: [])
        end.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end

  describe "#native_csharp_tests" do
    subject(:dotnet_test) do
      Dependabot::SharedHelpers.run_shell_command(command, allow_unsafe_shell_command: true, cwd: cwd)
    end

    let(:command) do
      [
        "dotnet",
        "test",
        "--configuration",
        "Release",
        "--tl:off",
        "--logger",
        "\"console;verbosity=normal\"",
        project_path
      ].join(" ")
    end

    let(:cwd) do
      File.join(dependabot_home, "nuget", "helpers", "lib", "NuGetUpdater")
    end

    context "when the output is from `dotnet test NuGetUpdater.Core.Test` output" do
      let(:project_path) do
        File.join(dependabot_home, "nuget", "helpers", "lib", "NuGetUpdater",
                  "NuGetUpdater.Core.Test", "NuGetUpdater.Core.Test.csproj")
      end

      it "contains the expected output" do
        # In CI when the terminal logger is disabled by default in .NET 9 there is no
        # output from the test runner: https://github.com/dotnet/msbuild/issues/10682.
        # Instead we have to rely on the cmd invocation failing with a non-zero exit code
        # if any tests fail. Locally when the terminal logger is enabled we can check
        # there is an absence of any evidence of test failures in the output.
        # expect(dotnet_test).to include("Passed!")
        expect(dotnet_test).not_to include("Build failed")
      end
    end

    context "when the output is from `dotnet test NuGetUpdater.Cli.Test`" do
      let(:project_path) do
        File.join(dependabot_home, "nuget", "helpers", "lib", "NuGetUpdater",
                  "NuGetUpdater.Cli.Test", "NuGetUpdater.Cli.Test.csproj")
      end

      it "contains the expected output" do
        # In CI when the terminal logger is disabled by default in .NET 9 there is no
        # output from the test runner: https://github.com/dotnet/msbuild/issues/10682.
        # Instead we have to rely on the cmd invocation failing with a non-zero exit code
        # if any tests fail. Locally when the terminal logger is enabled we can check
        # there is an absence of any evidence of test failures in the output.
        # expect(dotnet_test).to include("Passed!")
        expect(dotnet_test).not_to include("Build failed")
      end
    end
  end

  describe "#native_csharp_format" do
    subject(:dotnet_test) do
      Dependabot::SharedHelpers.run_shell_command(command)
    end

    let(:command) do
      [
        "dotnet",
        "format",
        lib_path,
        "--exclude",
        except_path,
        "--verify-no-changes",
        "-v",
        "diag"
      ].join(" ")
    end

    context "when output is from `dotnet format NuGetUpdater` output" do
      let(:lib_path) do
        File.absolute_path(File.join("helpers", "lib", "NuGetUpdater"))
      end

      let(:except_path) { "helpers/lib/NuGet.Client" }

      it "contains the expected output" do
        expect(dotnet_test).to include("Format complete")
      end
    end
  end

  describe "#ensure_no_errors" do
    subject(:error_message) do
      described_class.ensure_no_errors(JSON.parse(json))

      # defaults to no error
      return nil
    rescue StandardError => e
      return e.to_s
    end

    context "when nothing is reported" do
      let(:json) { "{}" } # an empty object

      it { is_expected.to be_nil }
    end

    context "when the error is expclicitly none" do
      let(:json) do
        {
          ErrorType: "None"
        }.to_json
      end

      it { is_expected.to be_nil }
    end

    context "when an authentication failure is encountered" do
      let(:json) do
        {
          ErrorType: "AuthenticationFailure",
          ErrorDetails: "(some-source)"
        }.to_json
      end

      it { is_expected.to include(": (some-source)") }
    end

    context "when a file is missing" do
      let(:json) do
        {
          ErrorType: "MissingFile",
          ErrorDetails: "some.file"
        }.to_json
      end

      it { is_expected.to include("some.file not found") }
    end

    context "when an update is not possible" do
      let(:json) do
        {
          ErrorType: "UpdateNotPossible",
          ErrorDetails: [
            "dependency 1",
            "dependency 2"
          ]
        }.to_json
      end

      it { is_expected.to include("dependency 1, dependency 2") }
    end

    context "when any other error is returned" do
      let(:json) do
        {
          ErrorType: "Unknown",
          ErrorDetails: "some error details"
        }.to_json
      end

      it { is_expected.to include("some error details") }
    end
  end
end
