# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nix/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Nix::FileUpdater do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "nixpkgs",
      version: "new_sha_abc123",
      previous_version: "3030f185ba6a4bf4f18b87f345f104e6a6961f34",
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        source: {
          type: "git",
          url: "https://github.com/NixOS/nixpkgs",
          branch: "nixos-unstable",
          ref: "nixos-unstable"
        },
        groups: []
      }],
      previous_requirements: [{
        file: "flake.lock",
        requirement: nil,
        source: {
          type: "git",
          url: "https://github.com/NixOS/nixpkgs",
          branch: "nixos-unstable",
          ref: "nixos-unstable"
        },
        groups: []
      }],
      package_manager: "nix"
    )
  end
  let(:updater) do
    described_class.new(
      dependency_files: [flake_nix, flake_lock],
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  let(:flake_nix) do
    Dependabot::DependencyFile.new(
      name: "flake.nix",
      content: flake_nix_content
    )
  end

  let(:flake_lock) do
    Dependabot::DependencyFile.new(
      name: "flake.lock",
      content: flake_lock_content
    )
  end

  let(:flake_nix_content) do
    fixture("flake.nix")
  end

  let(:flake_lock_content) do
    fixture("flake.lock")
  end

  def fixture(filename)
    File.read(File.join(__dir__, "fixtures", filename))
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:updated_lock_content) do
      flake_lock_content.gsub(
        "3030f185ba6a4bf4f18b87f345f104e6a6961f34",
        "new_sha_abc123"
      )
    end

    before do
      allow(Dependabot::SharedHelpers)
        .to receive(:in_a_temporary_repo_directory)
        .and_yield
      allow(Dependabot::SharedHelpers)
        .to receive(:run_shell_command)
      allow(File).to receive(:write).and_call_original
      allow(File).to receive(:write).with("flake.nix", anything)
      allow(File).to receive(:write).with("flake.lock", anything)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("flake.lock").and_return(updated_lock_content)
    end

    it "returns one updated file" do
      expect(updated_files.length).to eq(1)
    end

    it "returns the updated flake.lock" do
      expect(updated_files.first.name).to eq("flake.lock")
    end

    it "calls nix flake update with the input name" do
      updated_files
      expect(Dependabot::SharedHelpers)
        .to have_received(:run_shell_command)
        .with("nix flake update nixpkgs", fingerprint: "nix flake update <input_name>")
    end
  end
end
