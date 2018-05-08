# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/update_checkers/rust/cargo/version_resolver"

RSpec.describe Dependabot::UpdateCheckers::Rust::Cargo::VersionResolver do
  subject(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      requirements_to_unlock: requirements_to_unlock,
      credentials: credentials
    )
  end

  let(:requirements_to_unlock) { :own }
  let(:credentials) do
    [{
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Cargo.toml",
      content: fixture("rust", "manifests", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Cargo.lock",
      content: fixture("rust", "lockfiles", lockfile_fixture_name)
    )
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
    [{ file: "Cargo.toml", requirement: string_req, groups: [], source: nil }]
  end
  let(:dependency_name) { "regex" }
  let(:dependency_version) { "0.1.41" }
  let(:string_req) { "0.1.41" }

  describe "latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    it { is_expected.to be >= Gem::Version.new("0.2.10") }

    context "without a lockfile" do
      let(:dependency_files) { [manifest] }
      it { is_expected.to be >= Gem::Version.new("0.2.10") }
    end

    context "with an optional dependency" do
      let(:manifest_fixture_name) { "optional_dependency" }
      let(:lockfile_fixture_name) { "optional_dependency" }
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "0.1.3" }
      let(:string_req) { "0.1.3" }

      it { is_expected.to eq(Gem::Version.new("1.0.0")) }
    end

    context "with a feature dependency, when the feature has been removed" do
      let(:manifest_fixture_name) { "feature_removed" }
      let(:lockfile_fixture_name) { "feature_removed" }
      let(:dependency_name) { "syntect" }
      let(:dependency_version) { "1.8.1" }
      let(:string_req) { "1.8" }

      it { is_expected.to be_nil }
    end

    context "with multiple versions available of the dependency" do
      let(:manifest_fixture_name) { "multiple_versions" }
      let(:lockfile_fixture_name) { "multiple_versions" }
      let(:dependency_name) { "rand" }
      let(:dependency_version) { "0.4.1" }
      let(:string_req) { "0.4" }

      it { is_expected.to eq(Gem::Version.new("0.4.2")) }

      context "when the dependency isn't top-level" do
        let(:manifest_fixture_name) { "multiple_versions_subdependency" }
        let(:lockfile_fixture_name) { "multiple_versions_subdependency" }
        let(:dependency_name) { "hyper" }
        let(:dependency_version) { "0.10.13" }
        let(:requirements) { [] }

        it { is_expected.to eq(Gem::Version.new("0.10.13")) }
      end
    end

    context "when the latest version is blocked" do
      let(:manifest_fixture_name) { "mdBook" }
      let(:lockfile_fixture_name) { "mdBook" }
      let(:dependency_name) { "elasticlunr-rs" }
      let(:dependency_version) { "2.0.0" }
      let(:string_req) { "2.0" }

      it { is_expected.to eq(Gem::Version.new("2.0.0")) }
    end

    context "when there is a workspace" do
      let(:dependency_files) { [manifest, lockfile, workspace_child] }
      let(:manifest_fixture_name) { "workspace_root" }
      let(:lockfile_fixture_name) { "workspace" }
      let(:workspace_child) do
        Dependabot::DependencyFile.new(
          name: "lib/sub_crate/Cargo.toml",
          content: fixture("rust", "manifests", "workspace_child")
        )
      end
      let(:dependency_name) { "log" }
      let(:dependency_version) { "0.4.0" }
      let(:string_req) { "2.0" }
      let(:requirements) do
        [{
          requirement: "=0.4.0",
          file: "lib/sub_crate/Cargo.toml",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it { is_expected.to eq(Gem::Version.new("0.4.1")) }
    end

    context "when not unlocking" do
      let(:requirements_to_unlock) { :none }

      it { is_expected.to eq(Gem::Version.new("0.1.80")) }
    end
  end
end
