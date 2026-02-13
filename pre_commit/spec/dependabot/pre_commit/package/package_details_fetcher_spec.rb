# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pre_commit/package/package_details_fetcher"
require "dependabot/pre_commit/helpers"

RSpec.describe Dependabot::PreCommit::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      ignored_versions: ignored_versions
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

  describe "#latest_version_tag" do
    subject(:latest_version_tag) { fetcher.latest_version_tag }

    context "when pinned to a version tag" do
      let(:reference) { "v4.4.0" }

      it "returns the latest version tag" do
        expect(latest_version_tag).to be_a(Hash)
        expect(latest_version_tag[:tag]).to eq("v6.0.0")
        expect(latest_version_tag[:version]).to be_a(Dependabot::PreCommit::Version)
        expect(latest_version_tag[:version].to_s).to eq("6.0.0")
      end
    end

    context "when pinned to a commit SHA" do
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

      it "returns the latest version tag" do
        expect(latest_version_tag).to be_a(Hash)
        expect(latest_version_tag[:version]).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { [">= 6.0.0"] }

      it "filters out ignored versions" do
        expect(latest_version_tag).to be_a(Hash)
        expect(latest_version_tag[:version].to_s.split(".").first.to_i).to be < 6
      end
    end
  end

  describe "#commit_sha_release" do
    subject(:commit_sha_release) { fetcher.commit_sha_release }

    context "when pinned to a commit SHA" do
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

      it "returns the latest tagged version (prioritizing tags over commits)" do
        expect(commit_sha_release).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "when not pinned to a commit SHA" do
      let(:reference) { "v4.4.0" }

      it "returns nil" do
        expect(commit_sha_release).to be_nil
      end
    end
  end

  describe "#version_tag_release" do
    subject(:version_tag_release) { fetcher.version_tag_release }

    context "when pinned to a version tag" do
      let(:reference) { "v4.4.0" }

      it "returns the latest version" do
        expect(version_tag_release).to be_a(Dependabot::PreCommit::Version)
        expect(version_tag_release.to_s).to eq("6.0.0")
      end
    end

    context "when not pinned to a version tag" do
      let(:reference) { "main" }
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

      it "returns nil" do
        expect(version_tag_release).to be_nil
      end
    end
  end
end
