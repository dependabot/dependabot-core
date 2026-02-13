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
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: github_credentials,
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
    subject(:latest_version) { checker.latest_version }

    context "when the dependency has a pinned version" do
      let(:reference) { "v4.4.0" }

      it "returns the latest version" do
        expect(latest_version).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "when the dependency is pinned to a commit SHA" do
      let(:reference) { "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e" }
      let(:dependency_version) { nil }

      it "returns the latest tagged version (prioritizing tags over commits)" do
        expect(latest_version).to be_a(Dependabot::PreCommit::Version)
        expect(latest_version.to_s).to eq("6.0.0")
      end
    end

    context "with shortened version ref" do
      let(:reference) { "v4.4" }

      it "can handle shortened version refs" do
        expect(latest_version).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { [">= 7.0.0"] }

      it "filters out ignored versions" do
        expect(latest_version).to be_a(Dependabot::PreCommit::Version)
        expect(latest_version.to_s.split(".").first.to_i).to be < 7
      end
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    it "returns updated requirements" do
      expect(updated_requirements).to be_an(Array)
    end

    context "when updating a version tag" do
      let(:reference) { "v4.4.0" }

      it "updates the ref in the source" do
        expect(updated_requirements.first[:source][:ref]).not_to eq(reference)
      end
    end

    context "when dependency is pinned to commit SHA without version tags" do
      let(:reference) { "abc123def456" }
      let(:dependency_version) { reference }
      let(:new_commit_sha) { "def789ghi012" }

      before do
        latest_version_finder = instance_double(
          Dependabot::PreCommit::UpdateChecker::LatestVersionFinder,
          latest_version_tag: nil, # No tags in repo
          latest_release: new_commit_sha
        )
        allow(Dependabot::PreCommit::UpdateChecker::LatestVersionFinder)
          .to receive(:new).and_return(latest_version_finder)

        git_checker = instance_double(
          Dependabot::GitCommitChecker,
          git_dependency?: true,
          pinned_ref_looks_like_commit_sha?: true,
          ref_looks_like_commit_sha?: true
        )

        allow(checker).to receive_messages(
          latest_version: new_commit_sha,
          git_commit_checker: git_checker
        )
      end

      it "falls back to using latest_version when no tags exist" do
        # When latest_version_tag is nil,
        # latest_commit_sha should fall back to latest_version
        expect(updated_requirements).to be_an(Array)
        expect(updated_requirements.first[:source][:ref]).to eq(new_commit_sha)
      end

      it "does not raise 'No files changed!' error" do
        expect { updated_requirements }.not_to raise_error
      end
    end
  end
end
