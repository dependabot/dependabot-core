# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/update_checkers/rust/cargo/file_preparer"
require "dependabot/update_checkers/rust/cargo/version_resolver"

RSpec.describe Dependabot::UpdateCheckers::Rust::Cargo::VersionResolver do
  subject(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
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
  let(:dependency_files) do
    Dependabot::UpdateCheckers::Rust::Cargo::FilePreparer.new(
      dependency_files: unprepared_dependency_files,
      dependency: dependency,
      unlock_requirement: true
    ).prepared_dependency_files
  end
  let(:unprepared_dependency_files) { [manifest, lockfile] }
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
    [{
      file: "Cargo.toml",
      requirement: string_req,
      groups: [],
      source: source
    }]
  end
  let(:dependency_name) { "regex" }
  let(:dependency_version) { "0.1.41" }
  let(:string_req) { "0.1.41" }
  let(:source) { nil }

  describe "latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    it { is_expected.to be >= Gem::Version.new("0.2.10") }

    context "without a lockfile" do
      let(:unprepared_dependency_files) { [manifest] }
      it { is_expected.to be >= Gem::Version.new("0.2.10") }
    end

    context "with a missing dependency" do
      let(:manifest_fixture_name) { "bare_version_specified" }
      let(:lockfile_fixture_name) { "missing_dependency" }

      it "raises a DependencyFileNotResolvable error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            # Test that the temporary path isn't included in the error message
            expect(error.message).to_not include("dependabot_20")

            # Test that the name of the missing dep is included
            expect(error.message).to include("memchr")
          end
      end
    end

    context "with a blank requirement string" do
      let(:manifest_fixture_name) { "blank_version" }
      let(:lockfile_fixture_name) { "blank_version" }
      let(:string_req) { nil }

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

    context "with a git dependency" do
      let(:manifest_fixture_name) { "git_dependency" }
      let(:lockfile_fixture_name) { "git_dependency" }
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:string_req) { nil }
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

        it { is_expected.to eq(dependency_version) }
      end
    end

    context "with a feature dependency, when the feature has been removed" do
      let(:manifest_fixture_name) { "feature_removed" }
      let(:lockfile_fixture_name) { "feature_removed" }
      let(:dependency_name) { "syntect" }
      let(:dependency_version) { "1.8.1" }
      let(:string_req) { "1.8" }

      it { is_expected.to eq(Gem::Version.new("1.8.1")) }
    end

    context "with multiple versions available of the dependency" do
      let(:manifest_fixture_name) { "multiple_versions" }
      let(:lockfile_fixture_name) { "multiple_versions" }
      let(:dependency_name) { "rand" }
      let(:dependency_version) { "0.4.1" }
      let(:string_req) { "0.4" }

      it { is_expected.to be >= Gem::Version.new("0.5.1") }

      context "when the dependency isn't top-level" do
        let(:manifest_fixture_name) { "multiple_versions_subdependency" }
        let(:lockfile_fixture_name) { "multiple_versions_subdependency" }
        let(:dependency_name) { "hyper" }
        let(:dependency_version) { "0.10.13" }
        let(:requirements) { [] }

        it { is_expected.to eq(Gem::Version.new("0.10.13")) }
      end
    end

    context "when there is a workspace" do
      let(:unprepared_dependency_files) do
        [manifest, lockfile, workspace_child]
      end
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

      it { is_expected.to be >= Gem::Version.new("0.4.4") }

      context "but it is not correctly set up" do
        let(:unprepared_dependency_files) do
          [manifest, workspace_child]
        end
        let(:manifest_fixture_name) { "workspace_root" }
        let(:workspace_child) do
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: fixture("rust", "manifests", "workspace_child"),
            directory: "/lib/sub_crate"
          )
        end
        let(:manifest) do
          Dependabot::DependencyFile.new(
            name: "../../Cargo.toml",
            content: fixture("rust", "manifests", "blank_version"),
            directory: "/lib/sub_crate"
          )
        end

        it "raises a DependencyFileNotResolvable error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              # Test that the temporary path isn't included in the error message
              expect(error.message).to_not include("dependabot_20")

              # Test that the right details are included
              expect(error.message).to include("wasn't a root")
            end
        end
      end
    end

    context "when not unlocking" do
      let(:dependency_files) { unprepared_dependency_files }
      it { is_expected.to eq(Gem::Version.new("0.1.80")) }
    end
  end
end
