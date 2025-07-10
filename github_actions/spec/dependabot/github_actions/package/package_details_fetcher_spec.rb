# typed: false
# frozen_string_literal: true

require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/github_actions/package/package_details_fetcher"
require "dependabot/github_actions/version"
require "dependabot/package/package_release"
require "spec_helper"

RSpec.describe Dependabot::GithubActions::Package::PackageDetailsFetcher do
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
  let(:fetcher) do
    described_class.new(
      dependency: dependency,
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

  describe "#latest_version" do
    subject(:latest_version) { fetcher.release_list_for_git_dependency }

    let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }

    context "when given a dependency has a branch reference" do
      let(:reference) { "master" }

      it { is_expected.to eq(tip_of_master) }
    end

    context "when given a dependency has a tag reference" do
      let(:reference) { "v1.0.1" }

      it { is_expected.to eq(Dependabot::GithubActions::Version.new("1.1.0")) }

      context "when the latest version is being ignored" do
        let(:ignored_versions) { [">= 1.1.0"] }

        it { is_expected.to eq(Dependabot::GithubActions::Version.new("1.0.4")) }
      end

      context "when all versions are being ignored" do
        let(:ignored_versions) { [">= 0"] }

        it "returns current version" do
          expect(latest_version).to be_nil
        end

        context "when raise_on_ignored is enabled" do
          let(:raise_on_ignored) { true }

          it "raises an error" do
            expect { latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
          end
        end
      end
    end

    context "when a git commit SHA pointing to the tip of a branch not named like a version" do
      let(:upload_pack_fixture) { "setup-node" }
      let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }
      let(:reference) { tip_of_master }

      it "considers the commit itself as the latest version" do
        expect(latest_version).to eq(tip_of_master)
      end
    end

    context "when using a dependency with multiple git refs" do
      include_context "with multiple git sources"

      it "returns the expected value" do
        expect(latest_version).to eq(Gem::Version.new("3.5.2"))
      end
    end

    context "when dealing with a realworld repository" do
      let(:upload_pack_fixture) { "github-action-push-to-another-repository" }
      let(:dependency_name) { "dependabot-fixtures/github-action-push-to-another-repository" }
      let(:dependency_version) { nil }

      let(:latest_commit_in_main) { "9e487f29582587eeb4837c0552c886bb0644b6b9" }
      let(:latest_commit_in_devel) { "c7563454dd4fbe0ea69095188860a62a19658a04" }

      context "when pinned to an up to date commit in the default branch" do
        let(:reference) { latest_commit_in_main }

        it "returns the expected value" do
          expect(latest_version).to eq(latest_commit_in_main)
        end
      end

      context "when pinned to an out of date commit in the default branch" do
        let(:reference) { "f4b9c90516ad3bdcfdc6f4fcf8ba937d0bd40465" }

        it "returns the expected value" do
          expect(latest_version).to eq(latest_commit_in_main)
        end
      end

      context "when pinned to an up to date commit in a non default branch" do
        let(:reference) { latest_commit_in_devel }

        it "returns the expected value" do
          expect(latest_version).to eq(latest_commit_in_devel)
        end
      end

      context "when pinned to an out of date commit in a non default branch" do
        let(:reference) { "96e7dec17bbeed08477b9edab6c3a573614b829d" }

        it "returns the expected value" do
          expect(latest_version).to eq(latest_commit_in_devel)
        end
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { fetcher.lowest_security_fix_version_tag }

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
        expect(lowest_security_fix_version).to eq((
          { tag: "v1",
            version: Dependabot::GithubActions::Version.new("1.0.0"),
            commit_sha: "d0b521928fa734513b5cd9c7d9d8e09db50e884a",
            tag_sha: "d0b521928fa734513b5cd9c7d9d8e09db50e884a" }
        ))
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { ["= 1.0.0"] }

      it "doesn't return ignored versions" do
        expect(lowest_security_fix_version).to eq(
          { commit_sha: "bb178d2de54771e6f9332a2b1d55546cf2bc3e08", tag: "v2",
            tag_sha: "bb178d2de54771e6f9332a2b1d55546cf2bc3e08",
            version: Dependabot::GithubActions::Version.new("2.0.0") }
        )
      end
    end
  end
end
