# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/cargo/update_checker"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/requirements_update_strategy"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Cargo::UpdateChecker do
  let(:dependency_version) { "0.1.38" }
  let(:dependency_name) { "time" }
  let(:requirements) do
    [{ file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "cargo"
    )
  end
  let(:lockfile_fixture_name) { "bare_version_specified" }
  let(:manifest_fixture_name) { "bare_version_specified" }
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Cargo.toml",
        content: fixture("manifests", manifest_fixture_name)
      ),
      Dependabot::DependencyFile.new(
        name: "Cargo.lock",
        content: fixture("lockfiles", lockfile_fixture_name)
      )
    ]
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:requirements_update_strategy) { nil }
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      requirements_update_strategy: requirements_update_strategy
    )
  end
  let(:crates_fixture_name) { "#{dependency_name}.json" }
  let(:crates_response) { fixture("crates_io_responses", crates_fixture_name) }
  let(:crates_url) { "https://crates.io/api/v1/crates/#{dependency_name}" }

  before do
    stub_request(:get, crates_url).to_return(status: 200, body: crates_response)
  end

  it_behaves_like "an update checker"

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "when given an up-to-date dependency" do
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
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .with(basic_auth: %w(x-access-token token))
          .to_return(
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

    context "with a git subdependency" do
      let(:manifest_fixture_name) { "git_subdependency" }
      let(:lockfile_fixture_name) { "git_subdependency" }

      let(:dependency_name) { "cranelift-bforest" }
      let(:dependency_version) { "ede366644f3777d43448367df1af86e52c21660b" }
      let(:requirements) { [] }
      let(:crates_response) { nil }

      it { is_expected.to be_nil }
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

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { checker.lowest_security_fix_version }

    it "finds the lowest available non-vulnerable version" do
      expect(lowest_security_fix_version).to eq(Gem::Version.new("0.1.39"))
    end

    context "with a security vulnerability" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "cargo",
            vulnerable_versions: ["<= 0.1.39"]
          )
        ]
      end

      it "finds the lowest available non-vulnerable version" do
        expect(lowest_security_fix_version).to eq(Gem::Version.new("0.1.40"))
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "delegates to VersionResolver" do
      expect(Dependabot::Cargo::UpdateChecker::VersionResolver)
        .to receive(:new)
        .and_call_original
      expect(checker.latest_resolvable_version)
        .to eq(Gem::Version.new("0.1.40"))
    end

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 0.1.40, < 2.0"] }

      it { is_expected.to eq(Gem::Version.new("0.1.39")) }
    end

    context "when all versions are being ignored" do
      let(:ignored_versions) { [">= 0"] }
      let(:raise_on_ignored) { true }

      it "raises an error" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::AllVersionsIgnored)
      end
    end

    context "with a git dependency" do
      before do
        git_url = "https://github.com/BurntSushi/utf8-ranges.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .with(basic_auth: %w(x-access-token token))
          .to_return(
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

      it { is_expected.to eq("be9b8dfcaf449453cbf83ac85260ee80323f4f77") }

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

        it { is_expected.to eq("be9b8dfcaf449453cbf83ac85260ee80323f4f77") }
      end
    end

    context "with a git subdependency" do
      let(:manifest_fixture_name) { "git_subdependency" }
      let(:lockfile_fixture_name) { "git_subdependency" }

      let(:dependency_name) { "cranelift-bforest" }
      let(:dependency_version) { "ede366644f3777d43448367df1af86e52c21660b" }
      let(:requirements) { [] }
      let(:crates_response) { nil }

      it { is_expected.to be_nil }
    end
  end

  describe "#preferred_resolvable_version" do
    subject { checker.preferred_resolvable_version }

    it { is_expected.to eq(Gem::Version.new("0.1.40")) }

    context "with an insecure version" do
      let(:dependency_version) { "0.1.38" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "cargo",
            vulnerable_versions: ["<= 0.1.38"]
          )
        ]
      end

      it { is_expected.to eq(Gem::Version.new("0.1.39")) }
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
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .with(basic_auth: %w(x-access-token token))
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "utf8-ranges"),
            headers: git_header
          )
      end

      it { is_expected.to eq("be9b8dfcaf449453cbf83ac85260ee80323f4f77") }

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
      expect(described_class::RequirementsUpdater)
        .to receive(:new)
        .with(
          requirements: requirements,
          updated_source: nil,
          target_version: "0.1.40",
          update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions
        )
        .and_call_original
      expect(checker.updated_requirements)
        .to eq(
          [{
            file: "Cargo.toml",
            requirement: "0.1.40",
            groups: [],
            source: nil
          }]
        )
    end

    context "with an insecure version" do
      let(:dependency_version) { "0.1.38" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "cargo",
            vulnerable_versions: ["<= 0.1.38"]
          )
        ]
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater)
          .to receive(:new)
          .with(
            requirements: requirements,
            updated_source: nil,
            target_version: "0.1.39",
            update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions
          )
          .and_call_original
        expect(checker.updated_requirements)
          .to eq(
            [{
              file: "Cargo.toml",
              requirement: "0.1.39",
              groups: [],
              source: nil
            }]
          )
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    it { is_expected.to be(true) }

    context "with the lockfile-only requirements update strategy set" do
      let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }

      it { is_expected.to be(false) }
    end
  end
end
