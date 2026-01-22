# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pre_commit/update_checker"
require "dependabot/pre_commit/metadata_finder"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::PreCommit::UpdateChecker do
  let(:upload_pack_fixture) { "pre-commit-hooks" }
  let(:git_commit_checker) do
    Dependabot::GitCommitChecker.new(
      dependency: dependency,
      credentials: github_credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end
  let(:service_pack_url) do
    "https://github.com/#{dependency_name}.git/info/refs" \
      "?service=git-upload-pack"
  end
  let(:reference) { "v4.4.0" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/#{dependency_name}",
      ref: reference,
      branch: nil
    }
  end
  let(:dependency_version) do
    return unless Dependabot::PreCommit::Version.correct?(reference)

    Dependabot::PreCommit::Version.new(reference).to_s
  end
  let(:dependency_name) { "pre-commit/pre-commit-hooks" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "https://github.com/#{dependency_name}",
      version: dependency_version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".pre-commit-config.yaml",
        source: dependency_source
      }],
      package_manager: "pre_commit"
    )
  end
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: github_credentials,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      update_cooldown: update_cooldown
    )
  end
  let(:update_cooldown) { nil }

  before do
    stub_request(:get, service_pack_url)
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    subject { checker.latest_version }

    context "when the dependency has a pinned version" do
      let(:reference) { "v4.4.0" }

      it "returns the latest version" do
        expect(subject).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "when the dependency is pinned to a commit SHA" do
      let(:reference) { "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e" }

      before do
        allow(git_commit_checker).to receive(:head_commit_for_current_branch).and_return("abc123")
        allow(git_commit_checker).to receive(:pinned?).and_return(true)
        allow(git_commit_checker).to receive(:pinned_ref_looks_like_commit_sha?).and_return(true)
        allow(git_commit_checker).to receive(:head_commit_for_pinned_ref).and_return("abc123def456")
        allow(git_commit_checker).to receive(:local_tag_for_pinned_sha).and_return(
          { tag: "v5.0.0", commit_sha: reference, tag_sha: reference }
        )
      end

      it "returns a version based on the latest tag" do
        expect(subject).to be_a(Dependabot::PreCommit::Version)
      end
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }

    it "returns updated requirements" do
      expect(subject).to be_an(Array)
    end

    context "when updating a version" do
      let(:reference) { "v4.4.0" }

      it "updates the ref in the source" do
        expect(subject.first[:source][:ref]).not_to eq(reference)
      end
    end
  end
end
