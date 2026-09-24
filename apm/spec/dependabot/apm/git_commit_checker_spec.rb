# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/apm/git_commit_checker"
require "dependabot/apm/version"

RSpec.describe Dependabot::Apm::GitCommitChecker do
  let(:dependency_name) { "microsoft/edge-ai" }
  let(:reference) { "v1.0.0" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: nil,
      requirements: [{
        requirement: nil,
        groups: [],
        file: "apm.yml",
        source: {
          type: "git",
          url: "https://github.com/#{dependency_name}",
          ref: reference,
          branch: nil
        }
      }],
      package_manager: "apm"
    )
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      credentials: github_credentials,
      ignored_versions: [],
      raise_on_ignored: false,
      consider_version_branches_pinned: false
    )
  end
  let(:service_pack_url) do
    "https://github.com/#{dependency_name}.git/info/refs?service=git-upload-pack"
  end

  before do
    stub_request(:get, service_pack_url)
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", "apm-package-edge-tags"),
        headers: { "content-type" => "application/x-git-upload-pack-advertisement" }
      )
  end

  describe "#pinned_ref_looks_like_version?" do
    subject { checker.pinned_ref_looks_like_version? }

    context "when pinned to a plain SemVer tag" do
      let(:reference) { "v1.2.0" }

      it { is_expected.to be(true) }
    end

    context "when pinned to a SemVer tag carrying build metadata" do
      let(:reference) { "v1.2.0+build.5" }

      it { is_expected.to be(true) }
    end

    context "when pinned to a non-SemVer four-segment tag" do
      let(:reference) { "v1.2.3.4" }

      # The shared VERSION_REGEX would accept this, after which building an
      # Apm::Version raises ArgumentError; the APM grammar rejects it instead.
      it { is_expected.to be(false) }
    end
  end

  describe "#local_tag_for_latest_version" do
    subject(:latest_tag) { checker.local_tag_for_latest_version }

    it "keeps build-metadata releases and ignores non-SemVer tags" do
      expect(latest_tag&.tag).to eq("v1.3.0+build.5")
      expect(latest_tag&.version).to eq(Dependabot::Apm::Version.new("1.3.0+build.5"))
    end
  end
end
