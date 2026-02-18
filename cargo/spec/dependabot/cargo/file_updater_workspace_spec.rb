# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/file_updater"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"

RSpec.describe Dependabot::Cargo::FileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: []
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/test-repo",
      directory: "/"
    )
  end

  context "when updating workspace dependencies" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "Cargo.toml",
          content: fixture("manifests", "workspace_dependencies", "Cargo.toml")
        ),
        Dependabot::DependencyFile.new(
          name: "fvm/Cargo.toml",
          content: fixture("manifests", "workspace_dependencies", "fvm", "Cargo.toml")
        ),
        Dependabot::DependencyFile.new(
          name: "sdk/Cargo.toml",
          content: fixture("manifests", "workspace_dependencies", "sdk", "Cargo.toml")
        ),
        Dependabot::DependencyFile.new(
          name: "Cargo.lock",
          content: fixture("manifests", "workspace_dependencies", "Cargo.lock")
        )
      ]
    end
    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "wasmtime",
          version: "35.0.0",
          previous_version: "31.0.0",
          requirements: [
            {
              file: "Cargo.toml",
              requirement: "35.0.0",
              groups: ["workspace.dependencies"],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "Cargo.toml",
              requirement: "31.0.0",
              groups: ["workspace.dependencies"],
              source: nil
            }
          ],
          package_manager: "cargo"
        )
      ]
    end

    describe "#updated_dependency_files" do
      subject(:updated_files) { updater.updated_dependency_files }

      it "updates the workspace dependency in root Cargo.toml" do
        updated_cargo_toml = updated_files.find { |f| f.name == "Cargo.toml" }
        expect(updated_cargo_toml).not_to be_nil
        expect(updated_cargo_toml.content).to include('wasmtime = "35.0.0"')
        expect(updated_cargo_toml.content).not_to include('wasmtime = "31.0.0"')
      end

      it "does not modify member Cargo.toml files with workspace references" do
        member_cargo_toml = updated_files.find { |f| f.name == "fvm/Cargo.toml" }
        # Member file should not be included in updated files if unchanged
        expect(member_cargo_toml).to be_nil
      end

      it "updates the Cargo.lock file" do
        updated_lock = updated_files.find { |f| f.name == "Cargo.lock" }
        expect(updated_lock).not_to be_nil
        # Lock file updater should handle version changes
      end
    end

    context "with complex workspace dependency formats" do
      let(:complex_workspace_toml) do
        <<~TOML
          [workspace]
          members = ["member"]

          [workspace.dependencies]
          # Unquoted version
          anyhow = 1.0.86
          # Quoted version
          serde = "1.0.164"
          # Inline table
          thiserror = { version = "1.0.50" }
        TOML
      end

      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: complex_workspace_toml
          )
        ]
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "anyhow",
            version: "1.0.90",
            previous_version: "1.0.86",
            requirements: [
              {
                file: "Cargo.toml",
                requirement: "1.0.90",
                groups: ["workspace.dependencies"],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "Cargo.toml",
                requirement: "1.0.86",
                groups: ["workspace.dependencies"],
                source: nil
              }
            ],
            package_manager: "cargo"
          ),
          Dependabot::Dependency.new(
            name: "serde",
            version: "1.0.200",
            previous_version: "1.0.164",
            requirements: [
              {
                file: "Cargo.toml",
                requirement: "1.0.200",
                groups: ["workspace.dependencies"],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "Cargo.toml",
                requirement: "1.0.164",
                groups: ["workspace.dependencies"],
                source: nil
              }
            ],
            package_manager: "cargo"
          )
        ]
      end

      it "handles various TOML formats correctly" do
        updated_files = updater.updated_dependency_files
        updated_cargo = updated_files.find { |f| f.name == "Cargo.toml" }

        expect(updated_cargo.content).to include("anyhow = 1.0.90")
        expect(updated_cargo.content).to include('serde = "1.0.200"')
        expect(updated_cargo.content).to include("thiserror = { version = \"1.0.50\" }")
      end
    end
  end
end
