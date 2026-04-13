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
          branch: nil,
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
          branch: nil,
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

    context "with a branch-tracking input (ref unchanged)" do
      it "returns only the updated flake.lock" do
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.name).to eq("flake.lock")
      end

      it "calls nix flake update with the input name" do
        updated_files
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with("nix flake update nixpkgs", fingerprint: "nix flake update <input_name>")
      end
    end

    context "with a tag-pinned input (ref changed)" do
      let(:flake_nix_content) { fixture("flake_with_tag.nix") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "devenv",
          version: "new_sha_def456",
          previous_version: "old_sha_abc123",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "git",
              url: "https://github.com/cachix/devenv",
              branch: "v0.6.2",
              ref: "v0.6.2"
            },
            groups: []
          }],
          previous_requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "git",
              url: "https://github.com/cachix/devenv",
              branch: nil,
              ref: "v0.5"
            },
            groups: []
          }],
          package_manager: "nix"
        )
      end

      let(:updated_lock_content) { '{"updated": true}' }

      it "returns both flake.nix and flake.lock" do
        expect(updated_files.length).to eq(2)
        expect(updated_files.map(&:name)).to contain_exactly("flake.nix", "flake.lock")
      end

      it "rewrites the tag in flake.nix" do
        nix_file = updated_files.find { |f| f.name == "flake.nix" }
        expect(nix_file.content).to include('"github:cachix/devenv/v0.6.2"')
        expect(nix_file.content).not_to include('"github:cachix/devenv/v0.5"')
      end

      it "preserves other inputs in flake.nix" do
        nix_file = updated_files.find { |f| f.name == "flake.nix" }
        expect(nix_file.content).to include('"github:NixOS/nixpkgs/nixos-unstable"')
        expect(nix_file.content).to include('"github:numtide/flake-utils"')
      end

      it "writes the updated flake.nix before running nix" do
        updated_files
        expect(File).to have_received(:write)
          .with("flake.nix", a_string_including("github:cachix/devenv/v0.6.2"))
      end
    end
  end
end
