# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/cargo/file_updater/workspace_manifest_updater"

RSpec.describe Dependabot::Cargo::FileUpdater::WorkspaceManifestUpdater do
  let(:updater) do
    described_class.new(
      manifest: manifest,
      dependencies: [dependency]
    )
  end

  let(:manifest) do
    Dependabot::DependencyFile.new(name: "Cargo.toml", content: manifest_body)
  end
  let(:manifest_body) { fixture("manifests", manifest_fixture_name) }
  let(:manifest_fixture_name) { "workspace_dependencies_git_tag" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      previous_version: dependency_previous_version,
      previous_requirements: previous_requirements,
      package_manager: "cargo"
    )
  end
  let(:dependency_name) { "utf8-ranges" }
  let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
  let(:dependency_previous_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
  let(:requirements) { previous_requirements }
  let(:previous_requirements) do
    [{
      file: "Cargo.toml",
      requirement: nil,
      groups: ["workspace.dependencies"],
      source: {
        type: "git",
        url: "https://github.com/BurntSushi/utf8-ranges",
        branch: nil,
        ref: "0.1.3"
      }
    }]
  end

  describe "#updated_manifest_content" do
    subject(:updated_manifest_content) { updater.updated_manifest_content }

    context "when no files have changed" do
      it { is_expected.to eq(manifest.content) }
    end

    context "when the requirement has changed" do
      let(:manifest_fixture_name) { "workspace_dependencies_root" }
      let(:dependency_name) { "log" }
      let(:dependency_version) { "0.5.0" }
      let(:dependency_previous_version) { "0.4.0" }
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: "=0.5.0",
          groups: ["workspace.dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "Cargo.toml",
          requirement: "=0.4.0",
          groups: ["workspace.dependencies"],
          source: nil
        }]
      end

      it { is_expected.to include(%(log = "=0.5.0")) }
      it { is_expected.not_to include(%(log = "=0.4.0")) }
    end

    context "with a git dependency" do
      context "with an updated tag" do
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: nil,
            groups: ["workspace.dependencies"],
            source: {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: "1.0.0"
            }
          }]
        end

        it { is_expected.to include(', tag = "1.0.0" }') }

        context "with table header notation" do
          let(:manifest_fixture_name) { "workspace_dependencies_git_tag_table" }

          it { is_expected.to include(%(tag = "1.0.0")) }
          it { is_expected.not_to include(%(tag = "0.1.3")) }
        end
      end

      context "with an updated rev" do
        let(:dependency_name) { "regex" }
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: nil,
            groups: ["workspace.dependencies"],
            source: {
              type: "git",
              url: "https://github.com/rust-lang/regex",
              branch: nil,
              ref: "83141b376b93484341c68fbca3ca110ae5cd2708"
            }
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Cargo.toml",
            requirement: nil,
            groups: ["workspace.dependencies"],
            source: {
              type: "git",
              url: "https://github.com/rust-lang/regex",
              branch: nil,
              ref: "d5094c7e9456f2965dec20de671094a98c6929c2"
            }
          }]
        end

        it { is_expected.to include(%(rev = "83141b376b93484341c68fbca3ca110ae5cd2708")) }

        context "with table header notation" do
          let(:manifest_fixture_name) { "workspace_dependencies_git_tag_table" }

          it { is_expected.to include(%(rev = "83141b376b93484341c68fbca3ca110ae5cd2708")) }
          it { is_expected.not_to include(%(rev = "d5094c7e9456f2965dec20de671094a98c6929c2")) }
        end
      end
    end

    context "when dependency is not a workspace dependency" do
      let(:dependency_name) { "other-dep" }
      let(:dependency_version) { "1.0.0" }
      let(:dependency_previous_version) { "0.9.0" }
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: "1.0.0",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "Cargo.toml",
          requirement: "0.9.0",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it { is_expected.to eq(manifest.content) }
    end
  end
end
