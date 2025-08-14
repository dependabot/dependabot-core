# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/file_updater"

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
      repo: "test/workspace-table-header",
      directory: "/"
    )
  end

  context "when updating workspace dependencies with table header notation" do
    context "with [workspace.dependencies.name] format" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["crates/*"]

              # Some inline dependencies
              [workspace.dependencies]
              serde = "1.0.150"

              # Table header notation dependencies
              [workspace.dependencies.anyhow]
              version = '1.0.70'

              [workspace.dependencies.clap]
              version = "4.2.0"
              features = ["derive", "env"]

              [workspace.dependencies.tokio]
              features = ["full", "tracing"]
              default-features = false
              version = '1.25.0'
            TOML
          )
        ]
      end

      context "when updating a table header notation dependency" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "anyhow",
              version: "1.0.80",
              previous_version: "1.0.70",
              requirements: [{
                requirement: "1.0.80",
                groups: ["workspace.dependencies"],
                file: "Cargo.toml",
                source: nil
              }],
              previous_requirements: [{
                requirement: "1.0.70",
                groups: ["workspace.dependencies"],
                file: "Cargo.toml",
                source: nil
              }],
              package_manager: "cargo"
            )
          ]
        end

        it "updates the version in the table header section preserving quote style" do
          updated_files = updater.updated_dependency_files
          updated_content = updated_files.find { |f| f.name == "Cargo.toml" }.content

          expect(updated_content).to include("[workspace.dependencies.anyhow]")
          # Single quotes should be preserved
          expect(updated_content).to include("version = '1.0.80'")
          expect(updated_content).not_to include("version = '1.0.70'")

          # Ensure other dependencies remain unchanged
          expect(updated_content).to include('serde = "1.0.150"')
          expect(updated_content).to include("[workspace.dependencies.clap]")
          expect(updated_content).to include('version = "4.2.0"')
        end
      end

      context "when updating single-quoted table header dependency (tokio)" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "tokio",
              version: "1.26.0",
              previous_version: "1.25.0",
              requirements: [{
                requirement: "1.26.0",
                groups: ["workspace.dependencies"],
                file: "Cargo.toml",
                source: nil
              }],
              previous_requirements: [{
                requirement: "1.25.0",
                groups: ["workspace.dependencies"],
                file: "Cargo.toml",
                source: nil
              }],
              package_manager: "cargo"
            )
          ]
        end

        it "updates version preserving single quotes" do
          updated_files = updater.updated_dependency_files
          updated_content = updated_files.find { |f| f.name == "Cargo.toml" }.content

          expect(updated_content).to include("[workspace.dependencies.tokio]")
          # Single quotes should be preserved when version is not first field
          expect(updated_content).to include("version = '1.26.0'")
          expect(updated_content).not_to include("version = '1.25.0'")
          expect(updated_content).to include('features = ["full", "tracing"]')
          expect(updated_content).to include("default-features = false")
        end
      end

      context "when updating multiple dependencies with mixed formats" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "serde",
              version: "1.0.160",
              previous_version: "1.0.150",
              requirements: [{
                requirement: "1.0.160",
                groups: ["workspace.dependencies"],
                file: "Cargo.toml",
                source: nil
              }],
              previous_requirements: [{
                requirement: "1.0.150",
                groups: ["workspace.dependencies"],
                file: "Cargo.toml",
                source: nil
              }],
              package_manager: "cargo"
            ),
            Dependabot::Dependency.new(
              name: "clap",
              version: "4.3.0",
              previous_version: "4.2.0",
              requirements: [{
                requirement: "4.3.0",
                groups: ["workspace.dependencies"],
                file: "Cargo.toml",
                source: nil
              }],
              previous_requirements: [{
                requirement: "4.2.0",
                groups: ["workspace.dependencies"],
                file: "Cargo.toml",
                source: nil
              }],
              package_manager: "cargo"
            )
          ]
        end

        it "updates both inline and table header notation dependencies" do
          updated_files = updater.updated_dependency_files
          updated_content = updated_files.find { |f| f.name == "Cargo.toml" }.content

          # Check inline format update
          expect(updated_content).to include('serde = "1.0.160"')

          # Check table header format update
          expect(updated_content).to include("[workspace.dependencies.clap]")
          expect(updated_content).to include('version = "4.3.0"')
          expect(updated_content).to include('features = ["derive", "env"]')
        end
      end
    end

    context "when dependency doesn't exist (no-error-on-no-change fix)" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [package]
              name = "my-app"
              version = "1.0.0"

              [dependencies]
              # Regular dependency, not workspace
              reqwest = "0.11.0"

              [workspace]
              members = ["crates/*"]

              [workspace.dependencies]
              tokio = "1.25.0"
            TOML
          )
        ]
      end

      let(:dependencies) do
        [
          # Try to update a dependency that doesn't exist in workspace.dependencies
          Dependabot::Dependency.new(
            name: "nonexistent",
            version: "2.0.0",
            previous_version: "1.0.0",
            requirements: [{
              requirement: "2.0.0",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            previous_requirements: [{
              requirement: "1.0.0",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            package_manager: "cargo"
          )
        ]
      end

      it "returns unchanged content without raising an error" do
        expect { updater.updated_dependency_files }.not_to raise_error

        updated_files = updater.updated_dependency_files
        updated_content = updated_files.find { |f| f.name == "Cargo.toml" }.content

        # Content should be unchanged
        expect(updated_content).to eq(files.first.content)
      end
    end

    context "with unquoted versions in table header notation" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["app"]

              [workspace.dependencies.governor]
              version = 0.10.0
              default-features = false

              [workspace.dependencies.sea-query]
              version = 0.31.0
            TOML
          )
        ]
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "governor",
            version: "0.10.1",
            previous_version: "0.10.0",
            requirements: [{
              requirement: "0.10.1",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            previous_requirements: [{
              requirement: "0.10.0",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            package_manager: "cargo"
          )
        ]
      end

      it "updates unquoted versions correctly" do
        updated_files = updater.updated_dependency_files
        updated_content = updated_files.find { |f| f.name == "Cargo.toml" }.content

        expect(updated_content).to include("version = 0.10.1")
        expect(updated_content).not_to include("version = 0.10.0")
        expect(updated_content).to include("default-features = false")
      end
    end
  end
end
