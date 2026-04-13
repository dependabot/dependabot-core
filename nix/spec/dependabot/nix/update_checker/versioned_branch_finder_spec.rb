# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/git_ref"
require "dependabot/nix/update_checker/versioned_branch_finder"

RSpec.describe Dependabot::Nix::UpdateChecker::VersionedBranchFinder do
  subject(:finder) do
    described_class.new(
      current_ref: current_ref,
      dependency: dependency,
      credentials: credentials
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "nixpkgs",
      version: "abc123",
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        groups: [],
        source: { type: "git", url: "https://github.com/NixOS/nixpkgs", branch: nil, ref: current_ref }
      }],
      package_manager: "nix"
    )
  end

  let(:git_metadata_fetcher) { instance_double(Dependabot::GitMetadataFetcher) }

  before do
    allow(Dependabot::GitMetadataFetcher).to receive(:new).and_return(git_metadata_fetcher)
  end

  describe "#versioned_branch?" do
    context "with a versioned branch like nixos-24.11" do
      let(:current_ref) { "nixos-24.11" }

      it { expect(finder.versioned_branch?).to be true }
    end

    context "with a versioned branch like release-24.11" do
      let(:current_ref) { "release-24.11" }

      it { expect(finder.versioned_branch?).to be true }
    end

    context "with a rolling branch like nixos-unstable" do
      let(:current_ref) { "nixos-unstable" }

      it { expect(finder.versioned_branch?).to be false }
    end

    context "with a plain branch like main" do
      let(:current_ref) { "main" }

      it { expect(finder.versioned_branch?).to be false }
    end

    context "with a semver tag like v0.5" do
      let(:current_ref) { "v0.5" }

      it { expect(finder.versioned_branch?).to be false }
    end

    context "with nixpkgs-24.11" do
      let(:current_ref) { "nixpkgs-24.11" }

      it { expect(finder.versioned_branch?).to be true }
    end

    context "with nixos-24.11-small" do
      let(:current_ref) { "nixos-24.11-small" }

      it { expect(finder.versioned_branch?).to be true }
    end

    context "with nixpkgs-24.11-darwin" do
      let(:current_ref) { "nixpkgs-24.11-darwin" }

      it { expect(finder.versioned_branch?).to be true }
    end

    context "with nixos-unstable-small" do
      let(:current_ref) { "nixos-unstable-small" }

      it { expect(finder.versioned_branch?).to be false }
    end
  end

  describe "#latest_versioned_branch" do
    let(:current_ref) { "nixos-24.11" }

    let(:remote_branches) do
      [
        Dependabot::GitRef.new(name: "nixos-24.05", commit_sha: "aaa111", ref_type: Dependabot::RefType::Head),
        Dependabot::GitRef.new(name: "nixos-24.11", commit_sha: "bbb222", ref_type: Dependabot::RefType::Head),
        Dependabot::GitRef.new(name: "nixos-25.05", commit_sha: "ccc333", ref_type: Dependabot::RefType::Head),
        Dependabot::GitRef.new(name: "nixos-unstable", commit_sha: "ddd444", ref_type: Dependabot::RefType::Head),
        Dependabot::GitRef.new(name: "v1.0", commit_sha: "eee555", ref_type: Dependabot::RefType::Tag)
      ]
    end

    before do
      allow(git_metadata_fetcher).to receive(:refs_for_upload_pack).and_return(remote_branches)
    end

    it "returns the latest versioned branch" do
      result = finder.latest_versioned_branch
      expect(result).to eq({ branch: "nixos-25.05", commit_sha: "ccc333" })
    end

    context "when there is no newer branch" do
      let(:remote_branches) do
        [
          Dependabot::GitRef.new(name: "nixos-24.05", commit_sha: "aaa111", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "nixos-24.11", commit_sha: "bbb222", ref_type: Dependabot::RefType::Head)
        ]
      end

      it "returns nil" do
        expect(finder.latest_versioned_branch).to be_nil
      end
    end

    context "with release-prefixed branches" do
      let(:current_ref) { "release-24.11" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "home-manager",
          version: "abc123",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: {
              type: "git", url: "https://github.com/nix-community/home-manager",
              branch: nil, ref: current_ref
            }
          }],
          package_manager: "nix"
        )
      end

      let(:remote_branches) do
        [
          Dependabot::GitRef.new(name: "release-24.05", commit_sha: "aaa111", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "release-24.11", commit_sha: "bbb222", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "release-25.05", commit_sha: "ccc333", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "main", commit_sha: "ddd444", ref_type: Dependabot::RefType::Head)
        ]
      end

      it "returns the latest branch with matching prefix" do
        result = finder.latest_versioned_branch
        expect(result).to eq({ branch: "release-25.05", commit_sha: "ccc333" })
      end
    end

    context "when multiple newer versions exist" do
      let(:remote_branches) do
        [
          Dependabot::GitRef.new(name: "nixos-24.11", commit_sha: "bbb222", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "nixos-25.05", commit_sha: "ccc333", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "nixos-25.11", commit_sha: "fff666", ref_type: Dependabot::RefType::Head)
        ]
      end

      it "returns the highest version" do
        result = finder.latest_versioned_branch
        expect(result).to eq({ branch: "nixos-25.11", commit_sha: "fff666" })
      end
    end

    context "with a non-versioned branch" do
      let(:current_ref) { "nixos-unstable" }

      it "returns nil" do
        expect(finder.latest_versioned_branch).to be_nil
      end
    end

    context "with a suffixed branch (nixos-24.11-small)" do
      let(:current_ref) { "nixos-24.11-small" }

      let(:remote_branches) do
        [
          Dependabot::GitRef.new(name: "nixos-24.11", commit_sha: "aaa111", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "nixos-24.11-small", commit_sha: "bbb222", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "nixos-25.05", commit_sha: "ccc333", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "nixos-25.05-small", commit_sha: "ddd444", ref_type: Dependabot::RefType::Head),
          Dependabot::GitRef.new(name: "nixos-25.05-aarch64", commit_sha: "eee555", ref_type: Dependabot::RefType::Head)
        ]
      end

      it "only matches branches with the same suffix" do
        result = finder.latest_versioned_branch
        expect(result).to eq({ branch: "nixos-25.05-small", commit_sha: "ddd444" })
      end
    end
  end
end
