# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/go/dep/latest_version_finder"

RSpec.describe Dependabot::UpdateCheckers::Go::Dep::LatestVersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end

  let(:ignored_versions) { [] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gopkg.toml",
        content: fixture("go", "gopkg_tomls", manifest_fixture_name)
      ),
      Dependabot::DependencyFile.new(
        name: "Gopkg.lock",
        content: fixture("go", "gopkg_locks", lockfile_fixture_name)
      )
    ]
  end
  let(:manifest_fixture_name) { "no_version.toml" }
  let(:lockfile_fixture_name) { "no_version.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "dep"
    )
  end
  let(:requirements) do
    [{ file: "Gopkg.toml", requirement: req_str, groups: [], source: source }]
  end
  let(:dependency_name) { "golang.org/x/text" }
  let(:dependency_version) { "0.2.0" }
  let(:req_str) { nil }
  let(:source) { { type: "default", source: "golang.org/x/text" } }

  let(:service_pack_url) do
    "https://github.com/golang/text.git/info/refs"\
    "?service=git-upload-pack"
  end
  before do
    stub_request(:get, service_pack_url).
      to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end
  let(:upload_pack_fixture) { "text" }

  describe "#latest_version" do
    subject { finder.latest_version }
    it { is_expected.to eq(Gem::Version.new("0.3.0")) }

    context "with a sub-dependency" do
      let(:requirements) { [] }
      it { is_expected.to eq(Gem::Version.new("0.3.0")) }
    end

    context "with a git source" do
      context "that specifies a branch" do
        let(:manifest_fixture_name) { "branch.toml" }
        let(:lockfile_fixture_name) { "branch.lock" }

        let(:source) do
          {
            type: "git",
            url: "https://github.com/golang/text",
            branch: "master",
            ref: nil
          }
        end

        before do
          repo_url = "https://api.github.com/repos/golang/text"
          stub_request(:get, repo_url + "/compare/v0.3.0...master").
            to_return(
              status: 200,
              body: commit_compare_response,
              headers: { "Content-Type" => "application/json" }
            )
        end

        context "that is behind the latest release" do
          let(:commit_compare_response) do
            fixture("github", "commit_compare_behind.json")
          end

          it { is_expected.to eq(Gem::Version.new("0.3.0")) }
        end

        context "that is diverged from the latest release" do
          let(:commit_compare_response) do
            fixture("github", "commit_compare_diverged.json")
          end

          it { is_expected.to eq("0605a8320aceb4207a5fb3521281e17ec2075476") }
        end
      end

      context "that specifies a tag" do
        let(:manifest_fixture_name) { "tag_as_revision.toml" }
        let(:lockfile_fixture_name) { "tag_as_revision.lock" }

        let(:source) do
          {
            type: "git",
            url: "https://github.com/golang/text",
            branch: nil,
            ref: "v0.2.0"
          }
        end

        before do
          repo_url = "https://api.github.com/repos/golang/text"
          stub_request(:get, repo_url + "/compare/v0.3.0...v0.2.0").
            to_return(
              status: 200,
              body: commit_compare_response,
              headers: { "Content-Type" => "application/json" }
            )
        end
        let(:commit_compare_response) do
          fixture("github", "commit_compare_behind.json")
        end

        it { is_expected.to eq(Gem::Version.new("0.3.0")) }

        context "specified as a version (and not version-like)" do
          let(:manifest_fixture_name) { "tag_as_version.toml" }
          let(:lockfile_fixture_name) { "tag_as_version.lock" }
          let(:dependency_name) { "github.com/globalsign/mgo" }
          let(:source) do
            {
              type: "git",
              url: "https://github.com/globalsign/mgo",
              branch: nil,
              ref: "r2018.04.23"
            }
          end
          let(:req_str) { nil }
          let(:dependency_version) { "r2018.04.23" }

          let(:service_pack_url) do
            "https://github.com/globalsign/mgo.git/info/refs"\
            "?service=git-upload-pack"
          end
          let(:upload_pack_fixture) { "mgo" }

          it { is_expected.to eq("r2018.06.15") }
        end

        context "that is up-to-date" do
          let(:commit_compare_response) do
            fixture("github", "commit_compare_identical.json")
          end

          # Still make an update as we wish to switch source declaration style.
          # (Could decide not to do this if it causes trouble.)
          it { is_expected.to eq(Gem::Version.new("0.3.0")) }
        end

        context "when the new version isn't a direct update to the old one" do
          let(:commit_compare_response) do
            fixture("github", "commit_compare_diverged.json")
          end

          # Still make an update as we wish to switch source declaration style.
          # (Could decide not to do this if it causes trouble.)
          it { is_expected.to eq("v0.3.0") }
        end
      end
    end
  end
end
