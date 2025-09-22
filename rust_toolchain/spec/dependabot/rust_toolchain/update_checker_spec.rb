# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"

require "dependabot/rust_toolchain/file_parser"
require "dependabot/rust_toolchain/update_checker"
require "dependabot/rust_toolchain/version"

require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::RustToolchain::UpdateChecker do
  subject(:update_checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      raise_on_ignored: raise_on_ignored
    )
  end

  let(:dependency_files) { [rust_toolchain_file] }
  let(:rust_toolchain_file) do
    Dependabot::DependencyFile.new(
      name: "rust-toolchain.toml",
      content: rust_toolchain_content
    )
  end
  let(:rust_toolchain_content) do
    <<~TOML
      [toolchain]
      channel = "1.72"
    TOML
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "rust",
      version: dependency_version,
      requirements: [
        {
          file: "rust-toolchain.toml",
          requirement: dependency_requirement,
          groups: [],
          source: nil
        }
      ],
      package_manager: "rust_toolchain"
    )
  end
  let(:dependency_version) { "1.72" }
  let(:dependency_requirement) { "1.72" }

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }

  let(:latest_version_finder) { instance_double(described_class::LatestVersionFinder) }

  before do
    allow(described_class::LatestVersionFinder)
      .to receive(:new)
      .and_return(latest_version_finder)
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    let(:latest_version) { Dependabot::RustToolchain::Version.new("1.73.0") }

    before do
      allow(latest_version_finder)
        .to receive(:latest_version)
        .and_return(latest_version)
    end

    it "delegates to latest_version_finder" do
      expect(update_checker.latest_version).to eq(latest_version)
      expect(latest_version_finder).to have_received(:latest_version)
    end

    context "when no latest version is available" do
      let(:latest_version) { nil }

      it "returns nil" do
        expect(update_checker.latest_version).to be_nil
      end
    end
  end

  describe "#latest_resolvable_version" do
    let(:latest_version) { Dependabot::RustToolchain::Version.new("1.73.0") }

    before do
      allow(latest_version_finder)
        .to receive(:latest_version)
        .and_return(latest_version)
    end

    it "returns the same as latest_version" do
      expect(update_checker.latest_resolvable_version).to eq(latest_version)
      expect(latest_version_finder).to have_received(:latest_version)
    end

    context "when latest_version returns a string" do
      let(:latest_version) { "stable" }

      it "returns the string version" do
        expect(update_checker.latest_resolvable_version).to eq("stable")
      end
    end
  end

  describe "#updated_requirements" do
    let(:latest_version) { Dependabot::RustToolchain::Version.new("1.73.0") }
    let(:requirements) do
      [
        {
          file: "rust-toolchain.toml",
          requirement: "1.72",
          groups: [],
          source: nil
        }
      ]
    end

    before do
      allow(dependency).to receive(:requirements).and_return(requirements)
      allow(latest_version_finder)
        .to receive(:latest_version)
        .and_return(latest_version)
    end

    it "returns updated requirements with latest version" do
      updated_reqs = update_checker.updated_requirements

      expect(updated_reqs).to eq(
        [
          {
            file: "rust-toolchain.toml",
            requirement: latest_version,
            groups: [],
            source: nil
          }
        ]
      )
    end

    context "with multiple requirements" do
      let(:requirements) do
        [
          {
            file: "rust-toolchain.toml",
            requirement: "1.72",
            groups: [],
            source: nil
          },
          {
            file: "other-file.toml",
            requirement: "1.72",
            groups: ["dev"],
            source: { type: "git" }
          }
        ]
      end

      it "updates all requirements" do
        updated_reqs = update_checker.updated_requirements

        expect(updated_reqs).to eq(
          [
            {
              file: "rust-toolchain.toml",
              requirement: latest_version,
              groups: [],
              source: nil
            },
            {
              file: "other-file.toml",
              requirement: latest_version,
              groups: ["dev"],
              source: { type: "git" }
            }
          ]
        )
      end
    end

    context "when latest version is a string" do
      let(:latest_version) { "stable" }

      it "uses the string version in requirements" do
        updated_reqs = update_checker.updated_requirements

        expect(updated_reqs).to eq(
          [
            {
              file: "rust-toolchain.toml",
              requirement: "stable",
              groups: [],
              source: nil
            }
          ]
        )
      end
    end
  end

  describe "#latest_version_resolvable_with_full_unlock?" do
    it "returns false" do
      expect(update_checker.send(:latest_version_resolvable_with_full_unlock?)).to be(false)
    end
  end

  describe "#updated_dependencies_after_full_unlock" do
    it "raises NotImplementedError" do
      expect { update_checker.send(:updated_dependencies_after_full_unlock) }
        .to raise_error(NotImplementedError)
    end
  end

  describe "#latest_version_finder" do
    it "creates a LatestVersionFinder with correct parameters" do
      allow(described_class::LatestVersionFinder)
        .to receive(:new)
        .with(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: security_advisories,
          cooldown_options: nil,
          raise_on_ignored: raise_on_ignored
        )
        .and_return(latest_version_finder)

      update_checker.send(:latest_version_finder)

      expect(described_class::LatestVersionFinder).to have_received(:new).with(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: credentials,
        ignored_versions: ignored_versions,
        security_advisories: security_advisories,
        cooldown_options: nil,
        raise_on_ignored: raise_on_ignored
      )
    end

    it "memoizes the result" do
      finder1 = update_checker.send(:latest_version_finder)
      finder2 = update_checker.send(:latest_version_finder)

      expect(finder1).to be(finder2)
      expect(described_class::LatestVersionFinder).to have_received(:new).once
    end
  end

  context "with different dependency versions" do
    context "when dependency version is a stability channel" do
      let(:dependency_version) { "stable" }
      let(:dependency_requirement) { "stable" }

      it "can still find latest version" do
        latest_version = Dependabot::RustToolchain::Version.new("1.73.0")
        allow(latest_version_finder)
          .to receive(:latest_version)
          .and_return(latest_version)

        expect(update_checker.latest_version).to eq(latest_version)
      end
    end

    context "when dependency version is a nightly channel" do
      let(:dependency_version) { "nightly-2023-12-25" }
      let(:dependency_requirement) { "nightly-2023-12-25" }

      it "can still find latest version" do
        latest_version = Dependabot::RustToolchain::Version.new("nightly-2023-12-26")
        allow(latest_version_finder)
          .to receive(:latest_version)
          .and_return(latest_version)

        expect(update_checker.latest_version).to eq(latest_version)
      end
    end

    context "when dependency version is a full semver" do
      let(:dependency_version) { "1.72.0" }
      let(:dependency_requirement) { "1.72.0" }

      it "can still find latest version" do
        latest_version = Dependabot::RustToolchain::Version.new("1.73.0")
        allow(latest_version_finder)
          .to receive(:latest_version)
          .and_return(latest_version)

        expect(update_checker.latest_version).to eq(latest_version)
      end
    end
  end

  context "with update cooldown options" do
    subject(:update_checker) do
      described_class.new(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: credentials,
        ignored_versions: ignored_versions,
        security_advisories: security_advisories,
        raise_on_ignored: raise_on_ignored,
        update_cooldown: update_cooldown
      )
    end

    let(:update_cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }

    it "passes cooldown options to latest_version_finder" do
      allow(described_class::LatestVersionFinder)
        .to receive(:new)
        .with(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: security_advisories,
          cooldown_options: update_cooldown,
          raise_on_ignored: raise_on_ignored
        )
        .and_return(latest_version_finder)

      update_checker.send(:latest_version_finder)

      expect(described_class::LatestVersionFinder).to have_received(:new).with(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: credentials,
        ignored_versions: ignored_versions,
        security_advisories: security_advisories,
        cooldown_options: update_cooldown,
        raise_on_ignored: raise_on_ignored
      )
    end
  end
end
