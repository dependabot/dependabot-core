# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/rust/cargo"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Rust::Cargo do
  it_behaves_like "an update checker"

  before do
    stub_request(:get, crates_url).to_return(status: 200, body: crates_response)
  end
  let(:crates_url) { "https://crates.io/api/v1/crates/#{dependency_name}" }
  let(:crates_response) do
    fixture("rust", "crates_io_responses", crates_fixture_name)
  end
  let(:crates_fixture_name) { "#{dependency_name}.json" }

  let(:checker) do
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
        name: "Cargo.toml",
        content: fixture("rust", "manifests", manifest_fixture_name)
      ),
      Dependabot::DependencyFile.new(
        name: "Cargo.lock",
        content: fixture("rust", "lockfiles", lockfile_fixture_name)
      )
    ]
  end
  let(:manifest_fixture_name) { "bare_version_specified" }
  let(:lockfile_fixture_name) { "bare_version_specified" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "cargo"
    )
  end
  let(:requirements) do
    [{ file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }]
  end
  let(:dependency_name) { "time" }
  let(:dependency_version) { "0.1.38" }

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      let(:dependency_version) { "0.1.40" }
      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(Gem::Version.new("0.1.40")) }

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 0.1.40, < 2.0"] }
      it { is_expected.to eq(Gem::Version.new("0.1.39")) }
    end

    context "when the crates.io link resolves to a redirect" do
      let(:redirect_url) { "https://crates.io/api/v1/crates/Time" }

      before do
        stub_request(:get, crates_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: crates_response)
      end

      it { is_expected.to eq(Gem::Version.new("0.1.40")) }
    end

    context "when the crates.io link fails at first" do
      before do
        stub_request(:get, crates_url).
          to_raise(Excon::Error::Timeout).then.
          to_return(status: 200, body: crates_response)
      end

      it { is_expected.to eq(Gem::Version.new("0.1.40")) }
    end

    context "when the crates link resolves to a 'Not Found' page" do
      before do
        stub_request(:get, crates_url).
          to_return(status: 404, body: crates_response)
      end
      let(:crates_fixture_name) { "not_found.json" }

      it { is_expected.to be_nil }
    end

    context "when the latest version is a pre-release" do
      let(:dependency_name) { "xdg" }
      let(:dependency_version) { "2.0.0" }
      it { is_expected.to eq(Gem::Version.new("2.1.0")) }

      context "and the user wants a pre-release" do
        context "because their current version is a pre-release" do
          let(:dependency_version) { "2.0.0-pre4" }
          it { is_expected.to eq(Gem::Version.new("3.0.0-pre1")) }
        end

        context "because their requirements say they want pre-releases" do
          let(:requirements) do
            [{
              file: "Cargo.toml",
              requirement: "~2.0.0-pre1",
              groups: ["dependencies"],
              source: nil
            }]
          end
          it { is_expected.to eq(Gem::Version.new("3.0.0-pre1")) }
        end
      end
    end

    context "with a git dependency" do
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: nil
          }
        }]
      end

      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: ["x-access-token", "token"]).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      it { is_expected.to eq("47afd3c09c6583afdf4083fc9644f6f64172c8f8") }

      context "with a version-like tag" do
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: nil,
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: "0.1.3"
            }
          }]
        end

        # The SHA of the next version tag
        it { is_expected.to eq("83141b376b93484341c68fbca3ca110ae5cd2708") }
      end

      context "with a non-version tag" do
        let(:dependency_version) { "gitsha" }
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: nil,
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: "something"
            }
          }]
        end

        it { is_expected.to eq(dependency_version) }
      end
    end

    context "with a path dependency" do
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: { type: "path" }
        }]
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    it "delegates to VersionResolver" do
      expect(Dependabot::UpdateCheckers::Rust::Cargo::VersionResolver).
        to receive(:new).
        and_call_original
      expect(checker.latest_resolvable_version).
        to eq(Gem::Version.new("0.1.40"))
    end

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 0.1.40, < 2.0"] }
      it { is_expected.to eq(Gem::Version.new("0.1.39")) }
    end

    context "with a git dependency" do
      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: ["x-access-token", "token"]).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:manifest_fixture_name) { "git_dependency" }
      let(:lockfile_fixture_name) { "git_dependency" }
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: source
        }]
      end
      let(:source) do
        {
          type: "git",
          url: "https://github.com/BurntSushi/utf8-ranges",
          branch: nil,
          ref: nil
        }
      end

      it { is_expected.to eq("47afd3c09c6583afdf4083fc9644f6f64172c8f8") }

      context "with a tag" do
        let(:manifest_fixture_name) { "git_dependency_with_tag" }
        let(:lockfile_fixture_name) { "git_dependency_with_tag" }
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: "0.1.3"
          }
        end

        # The SHA of the next version tag
        it { is_expected.to eq("83141b376b93484341c68fbca3ca110ae5cd2708") }
      end

      context "with an ssh URL" do
        let(:manifest_fixture_name) { "git_dependency_ssh" }
        let(:lockfile_fixture_name) { "git_dependency_ssh" }
        let(:source) do
          {
            type: "git",
            url: "ssh://git@github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: nil
          }
        end

        it { is_expected.to eq("47afd3c09c6583afdf4083fc9644f6f64172c8f8") }
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.send(:latest_resolvable_version_with_no_unlock) }
    let(:dependency_name) { "regex" }
    let(:dependency_version) { "0.1.41" }
    let(:requirements) do
      [{
        file: "Cargo.toml",
        requirement: "0.1.41",
        groups: ["dependencies"],
        source: nil
      }]
    end

    it { is_expected.to eq(Gem::Version.new("0.1.80")) }

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 0.1.60, < 2.0"] }
      it { is_expected.to eq(Gem::Version.new("0.1.59")) }
    end

    context "with a git dependency" do
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:manifest_fixture_name) { "git_dependency" }
      let(:lockfile_fixture_name) { "git_dependency" }
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: source
        }]
      end
      let(:source) do
        {
          type: "git",
          url: "https://github.com/BurntSushi/utf8-ranges",
          branch: nil,
          ref: nil
        }
      end
      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: ["x-access-token", "token"]).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      it { is_expected.to eq("47afd3c09c6583afdf4083fc9644f6f64172c8f8") }

      context "with a tag" do
        let(:manifest_fixture_name) { "git_dependency_with_tag" }
        let(:lockfile_fixture_name) { "git_dependency_with_tag" }
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: "0.1.3"
          }
        end

        it { is_expected.to eq(dependency_version) }
      end
    end

    context "with a path dependency" do
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: nil,
          groups: ["dependencies"],
          source: { type: "path" }
        }]
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#updated_requirements" do
    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: requirements,
          updated_source: nil,
          latest_version: "0.1.40",
          latest_resolvable_version: "0.1.40",
          library: false
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [{
            file: "Cargo.toml",
            requirement: "0.1.40",
            groups: [],
            source: nil
          }]
        )
    end
  end
end
