# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/nix/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Nix::UpdateChecker do
  let(:branch) { "nixos-unstable" }
  let(:url) { "https://github.com/NixOS/nixpkgs" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "nixpkgs",
      version: "3030f185ba6a4bf4f18b87f345f104e6a6961f34",
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        groups: [],
        source: { type: "git", url: url, branch: branch, ref: branch }
      }],
      package_manager: "nix"
    )
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  it_behaves_like "an update checker"

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when the dependency is outdated" do
      before { allow(checker).to receive(:latest_version).and_return("new_sha") }

      it { is_expected.to be_truthy }
    end

    context "when the dependency is up-to-date" do
      before do
        allow(checker)
          .to receive(:latest_version)
          .and_return("3030f185ba6a4bf4f18b87f345f104e6a6961f34")
      end

      it { is_expected.to be_falsey }
    end
  end

  describe "#updated_requirements" do
    context "for a non-nixpkgs input" do
      it "returns the existing requirements unchanged" do
        expect(checker.updated_requirements).to eq(dependency.requirements)
      end
    end

    context "for a nixpkgs input with a newer branch available" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "nixos-23.05",
          requirements: [{
            file: "flake.lock",
            requirement: "nixos-23.05",
            groups: [],
            source: {
              type: "git", url: url, branch: "nixos-23.05", ref: "nixos-23.05",
              commit_sha: "aabbccdd", nixpkgs: true
            }
          }],
          package_manager: "nix"
        )
      end

      before do
        branch_finder = instance_double(Dependabot::Nix::UpdateChecker::NixpkgsBranchFinder)
        allow(Dependabot::Nix::UpdateChecker::NixpkgsBranchFinder)
          .to receive(:new).and_return(branch_finder)
        allow(branch_finder).to receive(:latest_branch).and_return("nixos-23.11")
      end

      it "returns updated requirements with the new branch" do
        updated = checker.updated_requirements
        expect(updated.first[:requirement]).to eq("nixos-23.11")
        expect(updated.first[:source][:branch]).to eq("nixos-23.11")
        expect(updated.first[:source][:ref]).to eq("nixos-23.11")
      end
    end

    context "for a nixpkgs input already on the latest branch" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "nixos-23.11",
          requirements: [{
            file: "flake.lock",
            requirement: "nixos-23.11",
            groups: [],
            source: {
              type: "git", url: url, branch: "nixos-23.11", ref: "nixos-23.11",
              commit_sha: "aabbccdd", nixpkgs: true
            }
          }],
          package_manager: "nix"
        )
      end

      before do
        branch_finder = instance_double(Dependabot::Nix::UpdateChecker::NixpkgsBranchFinder)
        allow(Dependabot::Nix::UpdateChecker::NixpkgsBranchFinder)
          .to receive(:new).and_return(branch_finder)
        allow(branch_finder).to receive(:latest_branch).and_return(nil)
      end

      it "returns the existing requirements unchanged" do
        expect(checker.updated_requirements).to eq(dependency.requirements)
      end
    end
  end

  describe "#latest_version" do
    context "for a nixpkgs input" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "nixos-23.05",
          requirements: [{
            file: "flake.lock",
            requirement: "nixos-23.05",
            groups: [],
            source: {
              type: "git", url: url, branch: "nixos-23.05", ref: "nixos-23.05",
              commit_sha: "aabbccdd", nixpkgs: true
            }
          }],
          package_manager: "nix"
        )
      end

      it "returns the latest branch name when newer is available" do
        branch_finder = instance_double(Dependabot::Nix::UpdateChecker::NixpkgsBranchFinder)
        allow(Dependabot::Nix::UpdateChecker::NixpkgsBranchFinder)
          .to receive(:new).and_return(branch_finder)
        allow(branch_finder).to receive(:latest_branch).and_return("nixos-23.11")

        expect(checker.latest_version).to eq("nixos-23.11")
      end

      it "returns the current version when no newer branch is available" do
        branch_finder = instance_double(Dependabot::Nix::UpdateChecker::NixpkgsBranchFinder)
        allow(Dependabot::Nix::UpdateChecker::NixpkgsBranchFinder)
          .to receive(:new).and_return(branch_finder)
        allow(branch_finder).to receive(:latest_branch).and_return(nil)

        expect(checker.latest_version).to eq("nixos-23.05")
      end
    end
  end
end
