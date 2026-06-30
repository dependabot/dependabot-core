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

  describe "#latest_version" do
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

      it "returns the commit SHA of the latest tag" do
        expect(checker.latest_version).to eq("def456")
      end

      it "reports as updatable" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be true
      end
    end

    context "with a tag-pinned input whose latest tag is within its cooldown window" do
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
      let(:checker) do
        described_class.new(
          dependency: dependency,
          dependency_files: [],
          credentials: [],
          update_cooldown: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 90)
        )
      end

      before do
        git_checker = instance_double(Dependabot::GitCommitChecker)
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_checker)
        allow(git_checker).to receive_messages(
          git_dependency?: true,
          pinned_ref_looks_like_version?: true,
          local_tag_for_latest_version: nil
        )
      end

      it "makes no update while the tag is cooling down" do
        expect(checker.latest_version).to be_nil
      end

      it "reports as not updatable" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be false
      end
    end

    context "with a tag-pinned input already at latest" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "devenv",
          version: "def456",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: { type: "git", url: "https://github.com/cachix/devenv", branch: nil, ref: "v0.6.2" }
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

      it "returns the current version" do
        expect(checker.latest_version).to eq("def456")
      end

      it "reports as not updatable" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be false
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

      it "returns the commit SHA of the latest branch" do
        expect(checker.latest_version).to eq("ccc333")
      end

      it "reports as updatable" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be true
      end
    end

    context "with a versioned branch already at latest" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "ccc333",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: { type: "git", url: "https://github.com/NixOS/nixpkgs", branch: nil, ref: "nixos-25.05" }
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
          latest_versioned_branch: nil
        )
        allow(Dependabot::Nix::UpdateChecker::VersionedBranchFinder)
          .to receive(:new).and_return(branch_finder)
      end

      it "falls back to commit tracking" do
        allow(checker).to receive(:fetch_latest_version_for_commit).and_return("ddd444")
        expect(checker.latest_version).to eq("ddd444")
      end
    end

    context "with a branch-tracking input and cooldown filters every candidate" do
      let(:current_sha) { "6201e203d09599479a3b3450ed24fa81537ebc4e" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: current_sha,
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/NixOS/nixpkgs",
              branch: nil,
              ref: "nixos-unstable"
            }
          }],
          package_manager: "nix"
        )
      end
      let(:checker) do
        described_class.new(
          dependency: dependency,
          dependency_files: [],
          credentials: [],
          update_cooldown: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
        )
      end
      let(:available_versions) do
        [
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Nix::Version.new("0.0.0-0.2"),
            tag: "a9503707cb403de2b9a974c27d89031c73b84455",
            released_at: Time.now
          ),
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Nix::Version.new("0.0.0-0.1"),
            tag: "2a94098db537ad60347abdf0e4ba8f9434e37002",
            released_at: Time.now
          )
        ]
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
          versioned_branch?: false
        )
        allow(Dependabot::Nix::UpdateChecker::VersionedBranchFinder)
          .to receive(:new).and_return(branch_finder)

        package_details_fetcher = instance_double(
          Dependabot::Nix::Package::PackageDetailsFetcher,
          available_versions: available_versions
        )
        allow(Dependabot::Nix::Package::PackageDetailsFetcher)
          .to receive(:new).and_return(package_details_fetcher)
      end

      it "falls back to the current commit SHA" do
        expect(checker.latest_version).to eq(current_sha)
      end
    end

    context "with a NixOS channel tarball input that has a newer channel" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "bd0ff2d3eac24699c3664d5966b9ef36f388e2ca",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz",
              branch: nil,
              ref: "nixos-25.05"
            }
          }],
          package_manager: "nix"
        )
      end

      before do
        channel_finder = instance_double(
          Dependabot::Nix::UpdateChecker::ChannelVersionFinder,
          latest_channel: {
            channel: "nixos-26.05",
            url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
            commit_sha: "34268251cf55aa3d8c4c5e6f7a8b9c0d1e2f3a4b"
          }
        )
        allow(Dependabot::Nix::UpdateChecker::ChannelVersionFinder)
          .to receive(:new).and_return(channel_finder)
      end

      it "returns the revision of the newest channel" do
        expect(checker.latest_version).to eq("34268251cf55aa3d8c4c5e6f7a8b9c0d1e2f3a4b")
      end

      it "reports as updatable" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be true
      end
    end

    context "with a NixOS channel tarball input on the newest channel" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "bd0ff2d3eac24699c3664d5966b9ef36f388e2ca",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
              branch: nil,
              ref: "nixos-26.05"
            }
          }],
          package_manager: "nix"
        )
      end

      before do
        channel_finder = instance_double(
          Dependabot::Nix::UpdateChecker::ChannelVersionFinder,
          latest_channel: nil,
          current_channel_revision: "bd0ff2d3eac24699c3664d5966b9ef36f388e2ca"
        )
        allow(Dependabot::Nix::UpdateChecker::ChannelVersionFinder)
          .to receive(:new).and_return(channel_finder)
      end

      it "falls back to refreshing the current channel revision" do
        expect(checker.latest_version).to eq("bd0ff2d3eac24699c3664d5966b9ef36f388e2ca")
      end

      it "reports as not updatable when the revision is unchanged" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be false
      end
    end

    context "with a NixOS channel tarball input whose source omits the ref" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "bd0ff2d3eac24699c3664d5966b9ef36f388e2ca",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz",
              branch: nil
            }
          }],
          package_manager: "nix"
        )
      end

      before do
        channel_finder = instance_double(
          Dependabot::Nix::UpdateChecker::ChannelVersionFinder,
          latest_channel: {
            channel: "nixos-26.05",
            url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
            commit_sha: "34268251cf55aa3d8c4c5e6f7a8b9c0d1e2f3a4b"
          }
        )
        allow(Dependabot::Nix::UpdateChecker::ChannelVersionFinder)
          .to receive(:new).and_return(channel_finder)
      end

      it "parses the channel from the URL instead of crashing" do
        expect(checker.latest_version).to eq("34268251cf55aa3d8c4c5e6f7a8b9c0d1e2f3a4b")
        expect(Dependabot::Nix::UpdateChecker::ChannelVersionFinder)
          .to have_received(:new).with(hash_including(current_channel: "nixos-25.05"))
      end
    end

    context "with a NixOS channel tarball input using a non-xz suffix" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "bd0ff2d3eac24699c3664d5966b9ef36f388e2ca",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-25.05/nixexprs.tar.gz",
              branch: nil,
              ref: "nixos-25.05"
            }
          }],
          package_manager: "nix"
        )
      end

      before do
        channel_finder = instance_double(
          Dependabot::Nix::UpdateChecker::ChannelVersionFinder,
          latest_channel: {
            channel: "nixos-26.05",
            url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.gz",
            commit_sha: "34268251cf55aa3d8c4c5e6f7a8b9c0d1e2f3a4b"
          }
        )
        allow(Dependabot::Nix::UpdateChecker::ChannelVersionFinder)
          .to receive(:new).and_return(channel_finder)
      end

      it "passes the original extension to the channel finder" do
        checker.latest_version
        expect(Dependabot::Nix::UpdateChecker::ChannelVersionFinder)
          .to have_received(:new).with(hash_including(extension: "gz"))
      end

      it "updates the requirement URL preserving the suffix" do
        expect(checker.updated_requirements.first[:source][:url])
          .to eq("https://channels.nixos.org/nixos-26.05/nixexprs.tar.gz")
      end
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

    context "with a NixOS channel tarball input that has a newer channel" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "old_rev_aaa",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz",
              branch: nil,
              ref: "nixos-25.05"
            }
          }],
          package_manager: "nix"
        )
      end

      before do
        channel_finder = instance_double(
          Dependabot::Nix::UpdateChecker::ChannelVersionFinder,
          latest_channel: {
            channel: "nixos-26.05",
            url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
            commit_sha: "new_rev_bbb"
          }
        )
        allow(Dependabot::Nix::UpdateChecker::ChannelVersionFinder)
          .to receive(:new).and_return(channel_finder)
      end

      it "rewrites the channel ref and url" do
        updated = checker.updated_requirements
        expect(updated.first[:source][:ref]).to eq("nixos-26.05")
        expect(updated.first[:source][:url])
          .to eq("https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz")
      end
    end

    context "with a NixOS channel tarball input being refreshed" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "current_rev_ccc",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
              branch: nil,
              ref: "nixos-26.05"
            }
          }],
          package_manager: "nix"
        )
      end

      before do
        channel_finder = instance_double(
          Dependabot::Nix::UpdateChecker::ChannelVersionFinder,
          latest_channel: nil
        )
        allow(Dependabot::Nix::UpdateChecker::ChannelVersionFinder)
          .to receive(:new).and_return(channel_finder)
      end

      it "leaves the channel ref and url unchanged" do
        updated = checker.updated_requirements
        expect(updated.first[:source][:ref]).to eq("nixos-26.05")
        expect(updated.first[:source][:url])
          .to eq("https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz")
      end
    end
  end
end
