# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/github_actions/update_checker/latest_version_finder"

namespace = Dependabot::GithubActions::UpdateChecker
RSpec.describe namespace::LatestVersionFinder do
  let(:upload_pack_fixture) { "setup-node" }
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
  let(:reference) { "master" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/#{dependency_name}",
      ref: reference,
      branch: nil
    }
  end
  let(:dependency_version) do
    return unless Dependabot::GithubActions::Version.correct?(reference)

    Dependabot::GithubActions::Version.new(reference).to_s
  end
  let(:dependency_name) { "actions/setup-node" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        source: dependency_source,
        metadata: { declaration_string: "#{dependency_name}@master" }
      }],
      package_manager: "github_actions"
    )
  end
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: github_credentials,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end

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

  shared_context "with multiple git sources" do
    let(:upload_pack_fixture) { "checkout" }
    let(:dependency_name) { "actions/checkout" }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "actions/checkout",
        version: nil,
        package_manager: "github_actions",
        requirements: [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@v2.1.0" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.1.0",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@master" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "master",
            branch: nil
          }
        }]
      )
    end
  end

  describe "#latest_release" do
    subject(:latest_release) { finder.latest_release }

    let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }

    context "when given a dependency has a branch reference" do
      let(:reference) { "master" }

      it { is_expected.to eq(tip_of_master) }
    end

    context "when a dependency has a tag reference and a branch similar to the tag" do
      let(:upload_pack_fixture) { "download-artifact" }
      let(:reference) { "v2" }

      it { is_expected.to eq(Dependabot::GithubActions::Version.new("3")) }
    end

    context "when a git commit SHA pointing to the tip of a branch not named like a version" do
      let(:upload_pack_fixture) { "setup-node" }
      let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }
      let(:reference) { tip_of_master }

      it "considers the commit itself as the latest version" do
        expect(latest_release).to eq(tip_of_master)
      end
    end

    context "when a git commit SHA pointing to the tip of a branch named like a version" do
      let(:upload_pack_fixture) { "run-vcpkg" }

      context "when a branch named like a higher version" do
        let(:tip_of_v6) { "205a4bde2b6ddf941a102fb50320ea1aa9338233" }

        let(:reference) { tip_of_v6 }

        it { is_expected.to eq(Gem::Version.new("10.5")) }
      end

      context "when no branch named like a higher version" do
        let(:tip_of_v10) { "34684effe7451ea95f60397e56ba34c06daced68" }

        let(:reference) { tip_of_v10 }

        it { is_expected.to eq(Gem::Version.new("10.5")) }
      end
    end

    context "when using a dependency with multiple git refs" do
      include_context "with multiple git sources"

      it "returns the expected value" do
        expect(latest_release).to eq(Gem::Version.new("3.5.2"))
      end
    end
  end

  describe "#lowest_security_fix_release" do
    subject(:lowest_security_fix_release) { finder.lowest_security_fix_release }

    let(:upload_pack_fixture) { "ghas-to-csv" }
    let(:dependency_version) { "0.4.0" }
    let(:dependency_name) { "some-natalie/ghas-to-csv" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "github_actions",
          vulnerable_versions: ["< 1.0"]
        )
      ]
    end

    context "when a supported newer version is available" do
      it "updates to the least new supported version" do
        expect(lowest_security_fix_release).to eq(
          (
                    { tag: "v1",
                      version: Dependabot::GithubActions::Version.new("1.0.0"),
                      commit_sha: "d0b521928fa734513b5cd9c7d9d8e09db50e884a",
                      tag_sha: "d0b521928fa734513b5cd9c7d9d8e09db50e884a" }
                  )
        )
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { ["= 1.0.0"] }

      it "doesn't return ignored versions" do
        expect(lowest_security_fix_release).to eq(
          { commit_sha: "bb178d2de54771e6f9332a2b1d55546cf2bc3e08", tag: "v2",
            tag_sha: "bb178d2de54771e6f9332a2b1d55546cf2bc3e08",
            version: Dependabot::GithubActions::Version.new("2.0.0") }
        )
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lowest_resolvable_security_fix_version) { finder.lowest_security_fix_release }

    before do
      allow(finder)
        .to receive(:lowest_security_fix_release)
        .and_return(Dependabot::GithubActions::Version.new("2.0.0"))
    end

    it { is_expected.to eq(Dependabot::GithubActions::Version.new("2.0.0")) }
  end
end
