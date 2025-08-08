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
      repo: "test/workspace-edge-cases",
      directory: "/"
    )
  end

  context "with edge cases for workspace dependency updates" do
    context "with inline comments in TOML" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["app"]

              [workspace.dependencies]
              # Critical security dependency
              openssl = "0.10.45"  # TODO: update to 0.11 when ready
              serde = { version = "1.0.150" }  # Serialization framework
            TOML
          )
        ]
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "openssl",
            version: "0.10.55",
            previous_version: "0.10.45",
            requirements: [{
              requirement: "0.10.55",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            previous_requirements: [{
              requirement: "0.10.45",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            package_manager: "cargo"
          )
        ]
      end

      it "preserves comments when updating" do
        updated_files = updater.updated_dependency_files
        updated_content = updated_files.find { |f| f.name == "Cargo.toml" }.content

        expect(updated_content).to include("# Critical security dependency")
        expect(updated_content).to include("# TODO: update to 0.11 when ready")
        expect(updated_content).to include('openssl = "0.10.55"')
      end
    end

    context "with complex version constraints" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["lib"]

              [workspace.dependencies]
              # Test special characters in version constraints
              exact = "=1.2.3"
              caret = "^0.5.0"
              tilde = "~2.1"
              wildcard = "0.4.*"
              range = ">=1.0, <2.0"
              # This one has a similar name - make sure we don't update it
              exact-copy = "=1.2.3"
            TOML
          )
        ]
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "wildcard",
            version: "0.5.0",
            previous_version: "0.4.0",
            requirements: [{
              requirement: "0.5.*",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            previous_requirements: [{
              requirement: "0.4.*",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            package_manager: "cargo"
          ),
          Dependabot::Dependency.new(
            name: "range",
            version: "2.0.0",
            previous_version: "1.5.0",
            requirements: [{
              requirement: ">=2.0, <3.0",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            previous_requirements: [{
              requirement: ">=1.0, <2.0",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            package_manager: "cargo"
          )
        ]
      end

      it "updates complex version constraints with special characters correctly" do
        updated_files = updater.updated_dependency_files
        updated_content = updated_files.find { |f| f.name == "Cargo.toml" }.content

        # Updated versions
        expect(updated_content).to include('wildcard = "0.5.*"')
        expect(updated_content).to include('range = ">=2.0, <3.0"')

        # Unchanged versions
        expect(updated_content).to include('exact = "=1.2.3"')
        expect(updated_content).to include('caret = "^0.5.0"')
        expect(updated_content).to include('tilde = "~2.1"')
        expect(updated_content).to include('exact-copy = "=1.2.3"')
      end
    end

    context "with workspace dependencies in unusual positions" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [package]
              name = "root"
              version = "1.0.0"

              [dependencies]
              some-dep = "1.0"

              # Workspace section in middle of file
              [workspace]
              members = ["sub"]

              [dev-dependencies]
              test-dep = "2.0"

              # Workspace dependencies at end
              [workspace.dependencies]
              lazy_static = "1.4.0"
              regex = { version = "1.5.5", default-features = false }

              [profile.release]
              opt-level = 3
            TOML
          )
        ]
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "regex",
            version: "1.5.6",
            previous_version: "1.5.5",
            requirements: [{
              requirement: "1.5.6",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            previous_requirements: [{
              requirement: "1.5.5",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            package_manager: "cargo"
          )
        ]
      end

      it "updates workspace dependencies regardless of position" do
        updated_files = updater.updated_dependency_files
        updated_content = updated_files.find { |f| f.name == "Cargo.toml" }.content

        expect(updated_content).to include('regex = { version = "1.5.6", default-features = false }')
        # Ensure structure is preserved
        expect(updated_content.index("[workspace.dependencies]")).to be > updated_content.index("[dev-dependencies]")
        expect(updated_content).to include("[profile.release]")
      end
    end

    context "with TOML parsing edge cases" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["crate1"]

              [workspace.dependencies]
              # Dependency with features
              tokio = { version = "1.25", features = ["full", "test"] }
              # Path dependency
              local = { path = "../local" }
              # Regular dependency
              log = "0.4.17"
            TOML
          )
        ]
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "log",
            version: "0.4.18",
            previous_version: "0.4.17",
            requirements: [{
              requirement: "0.4.18",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            previous_requirements: [{
              requirement: "0.4.17",
              groups: ["workspace.dependencies"],
              file: "Cargo.toml",
              source: nil
            }],
            package_manager: "cargo"
          )
        ]
      end

      it "handles complex dependency formats" do
        updated_files = updater.updated_dependency_files
        updated_content = updated_files.find { |f| f.name == "Cargo.toml" }.content

        # Should update the log dependency
        expect(updated_content).to include('log = "0.4.18"')
        # Other dependencies should remain unchanged
        expect(updated_content).to include('tokio = { version = "1.25", features = ["full", "test"] }')
        expect(updated_content).to include('local = { path = "../local" }')
      end
    end
  end
end
