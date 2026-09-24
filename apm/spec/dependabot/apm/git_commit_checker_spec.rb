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
  let(:upload_pack_fixture) { "apm-package-edge-tags" }

  before do
    stub_request(:get, service_pack_url)
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
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

    context "with a virtual package that uses package-scoped tags" do
      let(:dependency_name) { "org/mono/skills/review" }

      context "when pinned to a `{name}--v{version}` tag" do
        let(:reference) { "review--v1.0.0" }

        it { is_expected.to be(true) }
      end

      context "when pinned to a `{name}-v{version}` tag" do
        let(:reference) { "review-v1.0.0" }

        it { is_expected.to be(true) }
      end

      context "when pinned to a `{name}_v{version}` tag" do
        let(:reference) { "review_v1.0.0" }

        it { is_expected.to be(true) }
      end

      context "when pinned to another package's scoped tag" do
        let(:reference) { "security--v1.0.0" }

        # The scoped prefix is scoped to this dependency's package name, so a
        # sibling package's tag in the same monorepo is not a version tag here.
        it { is_expected.to be(false) }
      end

      context "when pinned to a scoped but non-SemVer tag" do
        let(:reference) { "review--v1.2.3.4" }

        it { is_expected.to be(false) }
      end
    end
  end

  describe "#local_tag_for_latest_version" do
    subject(:latest_tag) { checker.local_tag_for_latest_version }

    it "keeps build-metadata releases and ignores non-SemVer tags" do
      expect(latest_tag&.tag).to eq("v1.3.0+build.5")
      expect(latest_tag&.version).to eq(Dependabot::Apm::Version.new("1.3.0+build.5"))
    end

    context "when two tags share a version but differ in build metadata" do
      let(:upload_pack_fixture) { "apm-package-build-metadata-ties" }
      let(:reference) { "v1.0.0" }

      # Build metadata is not part of SemVer precedence, so both v1.3.0 tags
      # compare equal. The tie must break deterministically on the highest full
      # tag string (`+build.9`), even though `+build.5` is advertised first.
      it "picks the highest full tag string" do
        expect(latest_tag&.tag).to eq("v1.3.0+build.9")
      end
    end

    context "with a virtual package that publishes package-scoped tags" do
      let(:upload_pack_fixture) { "apm-package-scoped-tags" }
      let(:dependency_name) { "org/mono/skills/review" }
      let(:reference) { "review--v1.0.0" }

      # Only this package's `review--v*` tags share the pinned prefix, so the
      # latest is `review--v1.5.0`; sibling `security--v9.0.0` and the other
      # scoped layouts are excluded rather than dragging in a wrong update.
      it "resolves the latest scoped tag for this package" do
        expect(latest_tag&.tag).to eq("review--v1.5.0")
        expect(latest_tag&.version).to eq(Dependabot::Apm::Version.new("1.5.0"))
      end
    end
  end
end
