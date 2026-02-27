# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pre_commit/update_checker/latest_version_finder"
require "dependabot/pre_commit/helpers"

RSpec.describe Dependabot::PreCommit::UpdateChecker::LatestVersionFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      cooldown_options: update_cooldown
    )
  end

  let(:dependency_name) { "pre-commit/pre-commit-hooks" }
  let(:reference) { "v4.4.0" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/#{dependency_name}",
      ref: reference,
      branch: nil
    }
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "https://github.com/#{dependency_name}",
      version: "4.4.0",
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".pre-commit-config.yaml",
        source: dependency_source
      }],
      package_manager: "pre_commit"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:update_cooldown) { nil }
  let(:service_pack_url) do
    "https://github.com/#{dependency_name}.git/info/refs?service=git-upload-pack"
  end

  before do
    stub_request(:get, service_pack_url)
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", "pre-commit-hooks"),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  describe "#latest_release" do
    subject(:latest_release) { finder.latest_release }

    context "when pinned to a version tag" do
      let(:reference) { "v4.4.0" }

      it "returns the latest version" do
        expect(latest_release).to be_a(Dependabot::PreCommit::Version)
        expect(latest_release.to_s).to eq("6.0.0")
      end
    end

    context "when pinned to a commit SHA with a known tag" do
      let(:reference) { "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/#{dependency_name}",
          version: nil,
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: dependency_source
          }],
          package_manager: "pre_commit"
        )
      end

      before do
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_pinned_sha).and_return("v4.4.0")
      end

      it "returns the latest tagged version" do
        expect(latest_release).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "when pinned to a commit SHA without a known tag" do
      let(:reference) { "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/#{dependency_name}",
          version: nil,
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: dependency_source
          }],
          package_manager: "pre_commit"
        )
      end

      before do
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_pinned_sha).and_return(nil)
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:head_commit_for_pinned_ref).and_return("abc123def456")
      end

      it "falls back to latest commit SHA" do
        expect(latest_release).to be_a(String)
      end
    end

    context "when pinned to a commit SHA with a frozen version comment" do
      let(:reference) { "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/#{dependency_name}",
          version: nil,
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: dependency_source,
            metadata: { comment: "# frozen: v4.4.0" }
          }],
          package_manager: "pre_commit"
        )
      end

      before do
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_pinned_sha).and_return(nil)
      end

      it "returns the latest tagged version using comment metadata" do
        expect(latest_release).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { [">= 6.0.0"] }

      it "filters out ignored versions" do
        expect(latest_release).to be_a(Dependabot::PreCommit::Version)
        expect(latest_release.to_s.split(".").first.to_i).to be < 6
      end
    end
  end

  describe "cooldown filtering" do
    let(:reference) { "v4.4.0" }

    context "with cooldown configured" do
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7
        )
      end

      it "accepts cooldown configuration without error" do
        expect { finder.latest_release }.not_to raise_error
        expect(finder.latest_release).to be_a(Dependabot::PreCommit::Version)
      end

      it "returns a version when cooldown is applied" do
        result = finder.latest_release
        expect(result).not_to be_nil
        expect(result).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "with nil cooldown" do
      let(:update_cooldown) { nil }

      it "returns latest version without filtering" do
        expect(finder.latest_release).to be_a(Dependabot::PreCommit::Version)
        expect(finder.latest_release.to_s).to eq("6.0.0")
      end
    end
  end

  describe "version precision" do
    context "with shortened version ref" do
      let(:reference) { "v4.4" }

      it "handles shortened version refs" do
        result = finder.latest_release
        expect(result).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "with full version ref" do
      let(:reference) { "v4.4.0" }

      it "handles full version refs" do
        result = finder.latest_release
        expect(result).to be_a(Dependabot::PreCommit::Version)
        expect(result.to_s).to eq("6.0.0")
      end
    end
  end
end
