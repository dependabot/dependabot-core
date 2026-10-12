# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/apm/file_updater/lockfile_updater"

RSpec.describe Dependabot::Apm::FileUpdater::LockfileUpdater do
  subject(:updated_lockfile_content) { lockfile_updater.updated_lockfile_content }

  let(:lockfile_updater) do
    described_class.new(
      dependencies: [dependency],
      lockfile: lockfile,
      manifest_content: "dependencies:\n  apm:\n    - microsoft/edge-ai#v1.2.0\n",
      credentials: [],
      repo_contents_path: nil
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "apm.lock.yaml", content: "lockfile_version: '1'\ndependencies: []\n")
  end
  let(:dependency) do
    requirement = lambda do |ref|
      {
        file: "apm.yml",
        requirement: nil,
        groups: [],
        source: { type: "git", url: "https://github.com/microsoft/edge-ai", ref: ref, branch: nil },
        metadata: { declaration_string: "microsoft/edge-ai#v1.0.0" }
      }
    end

    Dependabot::Dependency.new(
      name: "microsoft/edge-ai",
      version: "1.2.0",
      previous_version: "1.0.0",
      requirements: [requirement.call("v1.2.0")],
      previous_requirements: [requirement.call("v1.0.0")],
      package_manager: "apm"
    )
  end

  context "when apm lock succeeds" do
    before do
      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
        File.write("apm.lock.yaml", "lockfile_version: '1'\n# #{File.read('apm.yml').lines.last.strip}\n")
        ""
      end
    end

    it "returns the lockfile apm wrote for the updated manifest" do
      expect(updated_lockfile_content).to eq("lockfile_version: '1'\n# - microsoft/edge-ai#v1.2.0\n")
    end
  end

  context "when apm lock fails" do
    before do
      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock").and_raise(
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: apm_output, error_context: {})
      )
    end

    context "when a repository can't be authenticated" do
      let(:apm_output) do
        "Failed to download dependency x/y: Failed to clone repository x/y: Authentication failed for clone " \
          "on github.com. No token available.\nfatal: Authentication failed for 'https://github.com/x/y.git/'"
      end

      it "raises a GitDependenciesNotReachable error for the repository" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
          expect(error.dependency_urls).to eq(["https://github.com/x/y.git/"])
        end
      end
    end

    context "when a pinned branch no longer exists" do
      let(:apm_output) do
        "Failed to download dependency microsoft/edge-ai: Failed to clone repository: " \
          "fatal: Remote branch gone not found in upstream origin"
      end

      it "raises a GitDependencyReferenceNotFound error for the dependency" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependencyReferenceNotFound) do |error|
          expect(error.dependency).to eq("microsoft/edge-ai")
        end
      end
    end

    context "when a pinned reference can't be resolved" do
      let(:apm_output) do
        "Failed to download dependency microsoft/edge-ai: Reference 'v9.9.9' not found in repository " \
          "https://github.com/microsoft/edge-ai"
      end

      it "raises a GitDependencyReferenceNotFound error for the dependency" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependencyReferenceNotFound)
      end
    end

    context "when apm fails for any other reason" do
      let(:apm_output) { "Invalid apm.yml: dependencies.apm must be a list" }

      it "raises a DependencyFileNotResolvable error with apm's message" do
        expect { updated_lockfile_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /must be a list/)
      end
    end
  end
end
