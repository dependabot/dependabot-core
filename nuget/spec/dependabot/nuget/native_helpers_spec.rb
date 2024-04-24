# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget/native_helpers"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Nuget::NativeHelpers do
  let(:dependabot_home) { ENV.fetch("DEPENDABOT_HOME", nil) || Dir.home }

  describe "nuget updater command path" do
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

    subject(:command) do
      (command,) = Dependabot::Nuget::NativeHelpers.get_nuget_updater_tool_command(repo_root: repo_root,
                                                                                   proj_path: proj_path,
                                                                                   dependency: dependency,
                                                                                   is_transitive: is_transitive)
      command = command.gsub(/^.*NuGetUpdater.Cli/, "/path/to/NuGetUpdater.Cli") # normalize path for unit test
      command
    end

    it "returns a properly formatted command with spaces on the path" do
      expect(command).to eq("/path/to/NuGetUpdater.Cli update --repo-root /path/to/repo " \
                            '--solution-or-project /path/to/repo/src/some\ project/some_project.csproj ' \
                            "--dependency Some.Package --new-version 1.2.3 --previous-version 1.2.2 " \
                            "--verbose")
    end

    context "invoking tool with spaces in path generates expected warning" do
      before do
        allow(Dependabot.logger).to receive(:error)
      end

      it "the tool runs with command line arguments properly interpreted" do
        # This test will fail if the command line arguments weren't properly interpreted
        Dependabot::Nuget::NativeHelpers.run_nuget_updater_tool(repo_root: repo_root,
                                                                proj_path: proj_path,
                                                                dependency: dependency,
                                                                is_transitive: is_transitive,
                                                                credentials: [])
        expect(Dependabot.logger).to_not have_received(:error)
      end
    end
  end
end
