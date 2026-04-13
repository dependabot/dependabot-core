# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/nix/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Nix::UpdateChecker do
  let(:url) { "https://github.com/NixOS/nixpkgs" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "nixpkgs",
      version: "3030f185ba6a4bf4f18b87f345f104e6a6961f34",
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        groups: [],
        source: { type: "git", url: url, branch: nil, ref: "nixos-unstable" }
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

    before do
      git_checker = instance_double(Dependabot::GitCommitChecker)
      allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_checker)
      allow(git_checker).to receive_messages(git_dependency?: true, pinned_ref_looks_like_version?: false)
    end

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
    context "with a branch-tracking input" do
      before do
        git_checker = instance_double(Dependabot::GitCommitChecker)
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_checker)
        allow(git_checker).to receive_messages(git_dependency?: true, pinned_ref_looks_like_version?: false)
      end

      it "returns the existing requirements unchanged" do
        allow(checker).to receive(:latest_version).and_return("new_sha")
        expect(checker.updated_requirements).to eq(dependency.requirements)
      end
    end

    context "with a tag-pinned input" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "devenv",
          version: "abc123",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: { type: "git", url: "https://github.com/cachix/devenv", branch: nil, ref: "v0.5" }
          }],
          package_manager: "nix"
        )
      end

      before do
        git_checker = instance_double(Dependabot::GitCommitChecker)
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_checker)
        allow(git_checker).to receive_messages(
          git_dependency?: true,
          pinned_ref_looks_like_version?: true,
          local_tag_for_latest_version: {
            tag: "v0.6.2", commit_sha: "def456", tag_sha: "def456"
          }
        )
      end

      it "returns updated requirements with the new tag" do
        updated = checker.updated_requirements
        expect(updated.first[:source][:ref]).to eq("v0.6.2")
        expect(updated.first[:source][:branch]).to be_nil
      end
    end

    context "with a versioned branch input" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "abc123",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: { type: "git", url: "https://github.com/NixOS/nixpkgs", branch: nil, ref: "nixos-24.11" }
          }],
          package_manager: "nix"
        )
      end

      before do
        git_checker = instance_double(Dependabot::GitCommitChecker)
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_checker)
        allow(git_checker).to receive_messages(
          git_dependency?: true,
          pinned_ref_looks_like_version?: false
        )

        branch_finder = instance_double(
          Dependabot::Nix::UpdateChecker::VersionedBranchFinder,
          versioned_branch?: true,
          latest_versioned_branch: { branch: "nixos-25.05", commit_sha: "ccc333" }
        )
        allow(Dependabot::Nix::UpdateChecker::VersionedBranchFinder)
          .to receive(:new).and_return(branch_finder)
      end

      it "returns updated requirements with the new branch" do
        updated = checker.updated_requirements
        expect(updated.first[:source][:ref]).to eq("nixos-25.05")
        expect(updated.first[:source][:branch]).to be_nil
      end
    end
  end
end
