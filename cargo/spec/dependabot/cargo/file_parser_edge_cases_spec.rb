# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/file_parser"

RSpec.describe Dependabot::Cargo::FileParser do
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "test/workspace-edge-cases",
      directory: "/"
    )
  end

  context "with edge cases for workspace dependencies" do
    context "with mixed workspace inheritance styles" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["crate1", "crate2"]

              [workspace.dependencies]
              serde = "1.0"
              tokio = { version = "1.25", features = ["full"] }
              local-crate = { path = "../local" }
            TOML
          ),
          Dependabot::DependencyFile.new(
            name: "crate1/Cargo.toml",
            content: <<~TOML
              [package]
              name = "crate1"
              version = "0.1.0"

              [dependencies]
              # Mixed styles in same file
              serde.workspace = true
              tokio = { workspace = true }
              local-crate = { workspace = true, optional = true }
            TOML
          )
        ]
      end

      it "handles both dotted and table notation" do
        dependencies = parser.parse
        workspace_deps = dependencies.select do |dep|
          dep.requirements.any? { |r| r[:groups]&.include?("workspace.dependencies") }
        end

        expect(workspace_deps.map(&:name)).to match_array(%w(serde tokio local-crate))
      end
    end

    context "with workspace = true and additional fields" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["member"]

              [workspace.dependencies]
              async-trait = "0.1.68"
            TOML
          ),
          Dependabot::DependencyFile.new(
            name: "member/Cargo.toml",
            content: <<~TOML
              [package]
              name = "member"
              version = "0.1.0"

              [dependencies]
              # workspace = true with additional fields
              async-trait = { workspace = true, optional = true }
            TOML
          )
        ]
      end

      it "skips workspace inherited deps even with additional fields" do
        dependencies = parser.parse

        # Should only have one async-trait from workspace.dependencies
        async_trait_deps = dependencies.select { |d| d.name == "async-trait" }
        expect(async_trait_deps.count).to eq(1)
        expect(async_trait_deps.first.requirements.first[:groups]).to include("workspace.dependencies")
      end
    end

    context "with malformed workspace inheritance" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["broken"]

              [workspace.dependencies]
              regex = "1.5"
            TOML
          ),
          Dependabot::DependencyFile.new(
            name: "broken/Cargo.toml",
            content: <<~TOML
              [package]
              name = "broken"
              version = "0.1.0"

              [dependencies]
              # Various malformed cases
              regex1 = { workspace = "true" }  # String instead of boolean
              regex2 = { workspace = 1 }        # Number instead of boolean
              regex3 = { "workspace" = true }   # Quoted key
              regex = { workspace = true }      # Valid one
            TOML
          )
        ]
      end

      it "handles malformed workspace inheritance gracefully" do
        dependencies = parser.parse

        # Should only include the workspace.dependencies version
        regex_deps = dependencies.select { |d| d.name == "regex" }
        expect(regex_deps.count).to eq(1)

        # regex3 should not be included (it has workspace = true)
        expect(dependencies.map(&:name)).not_to include("regex3")

        # regex1 and regex2 are malformed - they have workspace set to non-boolean
        # values, so they're treated as regular deps. Since they have no version
        # specified, they may or may not be included depending on how the parser
        # handles missing versions. Let's check if they have nil versions:
        malformed_names = %w(regex1 regex2)
        malformed = dependencies.select { |d| malformed_names.include?(d.name) }
        malformed.each do |dep|
          # These should have no version requirement since workspace = "true"/1
          # is not a valid version specification
          expect(dep.requirements.first[:requirement]).to be_nil
        end
      end
    end

    context "with workspace dependency not defined in root" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["orphan"]

              [workspace.dependencies]
              # Only serde is defined
              serde = "1.0"
            TOML
          ),
          Dependabot::DependencyFile.new(
            name: "orphan/Cargo.toml",
            content: <<~TOML
              [package]
              name = "orphan"
              version = "0.1.0"

              [dependencies]
              serde = { workspace = true }
              # This references a non-existent workspace dependency
              tokio = { workspace = true }
            TOML
          )
        ]
      end

      it "skips workspace references even if not defined in root" do
        dependencies = parser.parse

        # Should only have serde, not tokio
        expect(dependencies.map(&:name)).to include("serde")
        expect(dependencies.map(&:name)).not_to include("tokio")
      end
    end

    context "with nested workspace members" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["crates/*", "tools/cli"]

              [workspace.dependencies]
              clap = "4.0"
            TOML
          ),
          Dependabot::DependencyFile.new(
            name: "crates/core/Cargo.toml",
            content: <<~TOML
              [package]
              name = "core"
              version = "0.1.0"

              [dependencies]
              clap = { workspace = true }
            TOML
          ),
          Dependabot::DependencyFile.new(
            name: "tools/cli/Cargo.toml",
            content: <<~TOML
              [package]
              name = "cli"
              version = "0.1.0"

              [dependencies]
              clap = { workspace = true, features = ["derive"] }
            TOML
          )
        ]
      end

      it "handles nested workspace members correctly" do
        dependencies = parser.parse

        # Should only have one clap from workspace.dependencies
        clap_deps = dependencies.select { |d| d.name == "clap" }
        expect(clap_deps.count).to eq(1)
        expect(clap_deps.first.requirements.first[:file]).to eq("Cargo.toml")
      end
    end

    context "with workspace.package inheritance" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: <<~TOML
              [workspace]
              members = ["shared"]

              [workspace.package]
              version = "1.0.0"
              authors = ["Test"]

              [workspace.dependencies]
              rand = "0.8"
            TOML
          ),
          Dependabot::DependencyFile.new(
            name: "shared/Cargo.toml",
            content: <<~TOML
              [package]
              name = "shared"
              version.workspace = true
              authors.workspace = true

              [dependencies]
              rand = { workspace = true }
            TOML
          )
        ]
      end

      it "focuses only on workspace.dependencies, not workspace.package" do
        dependencies = parser.parse

        # Should only have rand dependency
        expect(dependencies.map(&:name)).to eq(["rand"])

        # Should not try to parse version.workspace or authors.workspace
        expect(dependencies.map(&:name)).not_to include("version", "authors")
      end
    end
  end
end
