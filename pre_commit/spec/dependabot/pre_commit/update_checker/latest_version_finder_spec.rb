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

  describe "#latest_release_version" do
    subject(:latest_release_version) { finder.latest_release_version }

    context "when pinned to a version tag" do
      let(:reference) { "v4.4.0" }

      it "returns the latest version" do
        expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
        expect(latest_release_version.to_s).to eq("6.0.0")
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
        expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
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
        expect(latest_release_version).to be_a(String)
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
        expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { [">= 6.0.0"] }

      it "filters out ignored versions" do
        expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
        expect(latest_release_version.to_s.split(".").first.to_i).to be < 6
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
        expect { finder.latest_release_version }.not_to raise_error
        expect(finder.latest_release_version).to be_a(Dependabot::PreCommit::Version)
      end

      it "returns a version when cooldown is applied" do
        result = finder.latest_release_version
        expect(result).not_to be_nil
        expect(result).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "when the latest version is in cooldown" do
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
      end

      let(:older_tag) do
        {
          tag: "v5.0.0",
          version: Dependabot::PreCommit::Version.new("5.0.0"),
          commit_sha: "older_sha",
          tag_sha: "older_tag_sha"
        }
      end

      before do
        # The shared GitCommitChecker cooldown resolves tag dates and returns
        # the newest tag outside its cooldown window; here we drive the finder
        # with its result. Date resolution itself is covered by common's
        # git_commit_checker_spec.
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_latest_version_matching_existing_precision)
          .with(update_cooldown)
          .and_return(cooldown_selected)
      end

      context "when an older version is outside cooldown" do
        let(:cooldown_selected) { older_tag }

        it "falls back to that version" do
          expect(finder.latest_release_version.to_s).to eq("5.0.0")
        end

        it "exposes the cooldown-selected tag via latest_version_tag" do
          expect(finder.latest_version_tag).to eq(older_tag)
        end
      end

      context "when every candidate is in cooldown" do
        let(:cooldown_selected) { nil }

        it "keeps the current version" do
          expect(finder.latest_release_version.to_s).to eq("4.4.0")
        end

        it "returns nil from latest_version_tag" do
          expect(finder.latest_version_tag).to be_nil
        end
      end

      context "when only versions older than the current ref remain" do
        let(:cooldown_selected) do
          {
            tag: "v3.0.0",
            version: Dependabot::PreCommit::Version.new("3.0.0"),
            commit_sha: "old_sha",
            tag_sha: "old_tag_sha"
          }
        end

        it "does not move backwards and keeps the current version" do
          expect(finder.latest_release_version.to_s).to eq("4.4.0")
          expect(finder.latest_version_tag).to be_nil
        end
      end
    end

    context "with nil cooldown" do
      let(:update_cooldown) { nil }

      it "returns latest version without filtering" do
        expect(finder.latest_release_version).to be_a(Dependabot::PreCommit::Version)
        expect(finder.latest_release_version.to_s).to eq("6.0.0")
      end
    end

    context "when pinned to a SHA with a frozen version comment" do
      let(:reference) { "cef0300fd0fc4d2a87a85fa2093c6b283ea36f4b" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/#{dependency_name}",
          version: "cef0300fd0fc4d2a87a85fa2093c6b283ea36f4b",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: dependency_source,
            metadata: { comment: "# frozen: v5.0.0" }
          }],
          package_manager: "pre_commit"
        )
      end
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
      end

      before do
        # A SHA has no version precision to match against, so the finder uses
        # the non-precision shared cooldown and compares against the frozen
        # comment version (v5.0.0). The available release is a version (not a
        # SHA string), so this isn't treated as a plain SHA release.
        allow_any_instance_of(Dependabot::PreCommit::Package::PackageDetailsFetcher) # rubocop:disable RSpec/AnyInstance
          .to receive(:release_list_for_git_dependency)
          .and_return(Dependabot::PreCommit::Version.new("6.0.0"))
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_pinned_sha).and_return(nil)
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_latest_version)
          .with(update_cooldown)
          .and_return(selected_tag)
      end

      context "when a newer tag is outside cooldown" do
        let(:selected_tag) do
          {
            tag: "v6.0.0",
            version: Dependabot::PreCommit::Version.new("6.0.0"),
            commit_sha: "3e8a8703264a2f4a69428a0aa4dcb512790b2c8c",
            tag_sha: "sha6"
          }
        end

        it "uses the frozen comment version and returns the newer tag" do
          expect(finder.latest_release_version.to_s).to eq("6.0.0")
        end
      end

      context "when only v5.1.0 is outside cooldown" do
        let(:selected_tag) do
          {
            tag: "v5.1.0",
            version: Dependabot::PreCommit::Version.new("5.1.0"),
            commit_sha: "abc123",
            tag_sha: "sha51"
          }
        end

        it "does not flag all versions as in cooldown" do
          expect(finder.latest_release_version.to_s).to eq("5.1.0")
        end
      end
    end
  end

  describe "version precision" do
    context "with shortened version ref" do
      let(:reference) { "v4.4" }

      it "handles shortened version refs" do
        result = finder.latest_release_version
        expect(result).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "with full version ref" do
      let(:reference) { "v4.4.0" }

      it "handles full version refs" do
        result = finder.latest_release_version
        expect(result).to be_a(Dependabot::PreCommit::Version)
        expect(result.to_s).to eq("6.0.0")
      end
    end
  end
end
