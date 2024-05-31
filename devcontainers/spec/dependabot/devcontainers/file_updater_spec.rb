# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/devcontainers/file_updater"
require "dependabot/devcontainers/requirement"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Devcontainers::FileUpdater do
  subject(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end

  it_behaves_like "a dependency file updater"

  let(:repo_contents_path) { build_tmp_repo(project_name) }

  let(:files) { project_dependency_files(project_name, directory: directory) }
  let(:directory) { "/" }

  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end

  describe "#updated_dependency_files" do
    subject(:updated_dependency_files) { updater.updated_dependency_files }

    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "ghcr.io/codspace/versioning/foo",
          version: "2.11.1",
          previous_version: "1.1.0",
          requirements: [{
            requirement: "2",
            groups: ["feature"],
            file: ".devcontainer.json",
            source: nil
          }],
          previous_requirements: [{
            requirement: "1",
            groups: ["feature"],
            file: ".devcontainer.json",
            source: nil
          }],
          package_manager: "devcontainers"
        )
      ]
    end

    context "when there's only a devcontainer.json file" do
      let(:project_name) { "config_in_root" }

      it "updates the version in .devcontainer.json" do
        expect(updated_dependency_files.size).to eq(1)

        config = updated_dependency_files.first
        expect(config.name).to eq(".devcontainer.json")
        expect(config.content).to include("ghcr.io/codspace/versioning/foo:2\"")
      end
    end

    context "when there's both manifest and lockfile" do
      let(:project_name) { "manifest_and_lockfile" }

      it "updates the version in both files" do
        expect(updated_dependency_files.size).to eq(2)

        config = updated_dependency_files.find { |f| f.name == ".devcontainer.json" }
        expect(config.content).to include("ghcr.io/codspace/versioning/foo:2\"")

        lockfile = updated_dependency_files.find { |f| f.name == ".devcontainer-lock.json" }
        expect(lockfile.content).to include('"version": "2.11.1"')
      end
    end

    context "when there are multiple manifests, but only one needs updates" do
      let(:project_name) { "multiple_configs" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "ghcr.io/codspace/versioning/baz",
            version: "2.0.0",
            previous_version: "1.1.0",
            requirements: [{
              requirement: "2.0",
              groups: ["feature"],
              file: ".devcontainer/devcontainer.json",
              source: nil
            }],
            previous_requirements: [{
              requirement: "1.0",
              groups: ["feature"],
              file: ".devcontainer/devcontainer.json",
              source: nil
            }],
            package_manager: "devcontainers"
          )
        ]
      end

      it "updates the version in both manifests" do
        expect(updated_dependency_files.size).to eq(1)

        config = updated_dependency_files.first
        expect(config.name).to eq(".devcontainer/devcontainer.json")
        expect(config.content).to include("ghcr.io/codspace/versioning/baz:2.0\"")
      end
    end

    context "when there's both manifest and lockfile, but only the lockfile needs updates" do
      let(:project_name) { "updated_manifest_outdated_lockfile" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "ghcr.io/codspace/versioning/foo",
            version: "2.11.1",
            previous_version: "2.11.0",
            requirements: [{
              requirement: "2",
              groups: ["feature"],
              file: ".devcontainer.json",
              source: nil
            }],
            previous_requirements: [{
              requirement: "2",
              groups: ["feature"],
              file: ".devcontainer.json",
              source: nil
            }],
            package_manager: "devcontainers"
          )
        ]
      end

      it "updates the version in lockfile" do
        expect(updated_dependency_files.size).to eq(1)

        lockfile = updated_dependency_files.first
        expect(lockfile.name).to eq(".devcontainer-lock.json")
        expect(lockfile.content).to include('"version": "2.11.1"')
      end
    end

    context "when a custom directory is configured" do
      let(:directory) { "src/go" }
      let(:project_name) { "multiple_roots" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "ghcr.io/devcontainers/features/common-utils",
            version: "2.4.0",
            previous_version: "2.3.2",
            requirements: [{
              requirement: "2",
              groups: ["feature"],
              file: ".devcontainer/devcontainer.json",
              source: nil
            }],
            previous_requirements: [{
              requirement: "2",
              groups: ["feature"],
              file: ".devcontainer/devcontainer.json",
              source: nil
            }],
            package_manager: "devcontainers"
          )
        ]
      end

      it "updates the version in lockfile" do
        expect(updated_dependency_files.size).to eq(1)

        config = updated_dependency_files.first
        expect(config.name).to eq(".devcontainer/devcontainer-lock.json")
        expect(config.content).to include("ghcr.io/devcontainers/features/common-utils:2")
        expect(config.content).to include('"version": "2.4.0"')
      end
    end

    context "when target version is not the latest" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "ghcr.io/codspace/versioning/foo",
            version: "2.10.0",
            previous_version: "1.1.0",
            requirements: [{
              requirement: "2",
              groups: ["feature"],
              file: ".devcontainer.json",
              source: nil
            }],
            previous_requirements: [{
              requirement: "2",
              groups: ["feature"],
              file: ".devcontainer.json",
              source: nil
            }],
            package_manager: "devcontainers"
          )
        ]
      end

      let(:project_name) { "updated_manifest_outdated_lockfile" }

      it "does not go past the target version in the lockfile" do
        expect(updated_dependency_files.size).to eq(1)

        lockfile = updated_dependency_files.first
        expect(lockfile.name).to eq(".devcontainer-lock.json")
        expect(lockfile.content).to include('"version": "2.10.0"')
      end
    end
  end
end
