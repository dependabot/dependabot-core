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
      dependencies: dependencies,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end
  let(:dependencies) { [dependency] }

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

  def dependency_for(name:, version:, previous_version:, url:, ref:, previous_ref:)
    Dependabot::Dependency.new(
      name: name,
      version: version,
      previous_version: previous_version,
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        source: {
          type: "git",
          url: url,
          branch: nil,
          ref: ref
        },
        groups: []
      }],
      previous_requirements: [{
        file: "flake.lock",
        requirement: nil,
        source: {
          type: "git",
          url: url,
          branch: nil,
          ref: previous_ref
        },
        groups: []
      }],
      package_manager: "nix"
    )
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
          .with("nix flake update nixpkgs", fingerprint: "nix flake update <input_names>")
      end
    end

    context "with grouped branch-tracking inputs" do
      let(:dependencies) { [dependency, home_manager_dependency] }

      let(:home_manager_dependency) do
        dependency_for(
          name: "home-manager",
          version: "new_home_manager_sha",
          previous_version: "old_home_manager_sha",
          url: "https://github.com/nix-community/home-manager",
          ref: nil,
          previous_ref: nil
        )
      end

      it "calls nix flake update with every input name" do
        updated_files
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with("nix flake update nixpkgs home-manager", fingerprint: "nix flake update <input_names>")
      end

      context "when the first input alone would not change the lockfile" do
        before do
          command = nil

          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command) do |actual_command, **_kwargs|
              command = actual_command
            end

          allow(File)
            .to receive(:read)
            .with("flake.lock") do
              if command == "nix flake update nixpkgs home-manager"
                updated_lock_content
              else
                flake_lock_content
              end
            end
        end

        it "does not treat the grouped update as unchanged" do
          expect { updated_files }.not_to raise_error
          expect(updated_files.map(&:name)).to eq(["flake.lock"])
        end
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
              branch: nil,
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

    context "with a versioned branch input (ref changed)" do
      let(:flake_nix_content) { fixture("flake_with_versioned_branch.nix") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "new_sha_def456",
          previous_version: "old_sha_abc123",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "git",
              url: "https://github.com/NixOS/nixpkgs",
              branch: nil,
              ref: "nixos-25.05"
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
              ref: "nixos-24.11"
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

      it "rewrites the branch in flake.nix" do
        nix_file = updated_files.find { |f| f.name == "flake.nix" }
        expect(nix_file.content).to include('"github:NixOS/nixpkgs/nixos-25.05"')
        expect(nix_file.content).not_to include("nixos-24.11")
      end
    end

    context "with grouped inputs that change refs" do
      let(:flake_nix_content) { fixture("flake_with_versioned_branch.nix") }
      let(:dependencies) { [dependency, home_manager_dependency] }
      let(:updated_lock_content) { '{"updated": true}' }

      let(:dependency) do
        dependency_for(
          name: "nixpkgs",
          version: "new_sha_def456",
          previous_version: "old_sha_abc123",
          url: "https://github.com/NixOS/nixpkgs",
          ref: "nixos-25.05",
          previous_ref: "nixos-24.11"
        )
      end

      let(:home_manager_dependency) do
        dependency_for(
          name: "home-manager",
          version: "new_home_manager_sha",
          previous_version: "old_home_manager_sha",
          url: "https://github.com/nix-community/home-manager",
          ref: "release-25.05",
          previous_ref: "release-24.11"
        )
      end

      it "rewrites all changed refs in flake.nix before running nix" do
        updated_files
        expect(File).to have_received(:write)
          .with("flake.nix", a_string_including("github:NixOS/nixpkgs/nixos-25.05"))
        expect(File).to have_received(:write)
          .with("flake.nix", a_string_including("github:nix-community/home-manager/release-25.05"))
      end
    end
  end
end
