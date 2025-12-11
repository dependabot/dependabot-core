# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/crystal_shards/update_checker"
require "dependabot/git_commit_checker"

RSpec.describe Dependabot::CrystalShards::UpdateChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: false,
      security_advisories: security_advisories,
      options: {}
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "kemal",
      version: "1.0.0",
      requirements: [{
        file: "shard.yml",
        requirement: "~> 1.0.0",
        groups: ["dependencies"],
        source: {
          type: "git",
          url: "https://github.com/kemalcr/kemal"
        }
      }],
      package_manager: "crystal_shards"
    )
  end

  let(:dependency_files) { [shard_yml] }

  let(:shard_yml) do
    Dependabot::DependencyFile.new(
      name: "shard.yml",
      content: <<~YAML
        name: my_shard
        version: 1.0.0

        dependencies:
          kemal:
            github: kemalcr/kemal
            version: ~> 1.0.0
      YAML
    )
  end

  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    context "when dependency is a git dependency" do
      before do
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:git_dependency?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned_ref_looks_like_version?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:local_tag_for_latest_version)
          .and_return({ tag: "v1.2.0", commit_sha: "abc123" })
      end

      it "returns the latest version from git tags" do
        expect(latest_version).to eq(Dependabot::CrystalShards::Version.new("1.2.0"))
      end
    end

    context "when dependency is a path dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "local_shard",
          version: "1.0.0",
          requirements: [{
            file: "shard.yml",
            requirement: nil,
            groups: ["dependencies"],
            source: {
              type: "path",
              path: "../local_shard"
            }
          }],
          package_manager: "crystal_shards"
        )
      end

      it "returns nil for path dependencies" do
        expect(latest_version).to be_nil
      end
    end

    context "when git tag lookup fails" do
      before do
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:git_dependency?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned_ref_looks_like_version?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:local_tag_for_latest_version).and_return(nil)
      end

      it "returns current version" do
        expect(latest_version).to eq("1.0.0")
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    context "when a newer version exists" do
      before do
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:git_dependency?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned_ref_looks_like_version?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:local_tag_for_latest_version)
          .and_return({ tag: "v1.2.0", commit_sha: "abc123" })
      end

      it "returns the latest resolvable version" do
        expect(latest_resolvable_version).to eq(Dependabot::CrystalShards::Version.new("1.2.0"))
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject(:result) { checker.latest_resolvable_version_with_no_unlock }

    context "when dependency is a git dependency" do
      before do
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:git_dependency?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:head_commit_for_current_branch).and_return("def456")
      end

      it "returns the head commit" do
        expect(result).to eq("def456")
      end
    end

    context "when dependency is a path dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "local_shard",
          version: "1.0.0",
          requirements: [{
            file: "shard.yml",
            requirement: nil,
            groups: ["dependencies"],
            source: {
              type: "path",
              path: "../local_shard"
            }
          }],
          package_manager: "crystal_shards"
        )
      end

      it "returns nil" do
        expect(result).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    before do
      allow_any_instance_of(Dependabot::GitCommitChecker)
        .to receive(:git_dependency?).and_return(true)
      allow_any_instance_of(Dependabot::GitCommitChecker)
        .to receive(:pinned?).and_return(false)
      allow_any_instance_of(Dependabot::GitCommitChecker)
        .to receive(:head_commit_for_current_branch).and_return(nil)
      allow_any_instance_of(Dependabot::GitCommitChecker)
        .to receive(:pinned_ref_looks_like_version?).and_return(false)
    end

    it "returns requirements array" do
      expect(updated_requirements).to be_an(Array)
      expect(updated_requirements.first).to include(:file, :requirement, :groups, :source)
    end
  end

  describe "#up_to_date?" do
    context "when no newer version exists" do
      before do
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:git_dependency?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned_ref_looks_like_version?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:local_tag_for_latest_version).and_return(nil)
      end

      it "returns true" do
        expect(checker.up_to_date?).to be true
      end
    end

    context "when a newer version exists" do
      before do
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:git_dependency?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:pinned_ref_looks_like_version?).and_return(true)
        allow_any_instance_of(Dependabot::GitCommitChecker)
          .to receive(:local_tag_for_latest_version)
          .and_return({ tag: "v1.2.0", commit_sha: "abc123" })
      end

      it "returns false" do
        expect(checker.up_to_date?).to be false
      end
    end
  end

  describe "#lowest_security_fix_version" do
    context "when not vulnerable" do
      it "returns nil" do
        expect(checker.lowest_security_fix_version).to be_nil
      end
    end
  end
end
