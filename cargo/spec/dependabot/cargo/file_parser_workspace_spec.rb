# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/file_parser"
require "dependabot/dependency_file"
require "dependabot/source"

RSpec.describe Dependabot::Cargo::FileParser do
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/test-repo",
      directory: "/"
    )
  end

  context "with workspace dependencies" do
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
          name: "Cargo.lock",
          content: fixture("manifests", "workspace_dependencies", "Cargo.lock")
        )
      ]
    end

    describe "#parse" do
      subject(:dependencies) { parser.parse }

      it "parses workspace dependencies from root Cargo.toml" do
        workspace_deps = dependencies.select do |dep|
          dep.requirements.any? { |r| r[:groups].include?("workspace.dependencies") }
        end

        expect(workspace_deps.map(&:name)).to match_array(%w(wasmtime serde thiserror anyhow))
      end

      it "does not include workspace-inherited dependencies from member manifests" do
        # These dependencies use { workspace = true } and should be skipped
        member_deps = dependencies.select do |dep|
          dep.requirements.any? { |r| r[:file] == "fvm/Cargo.toml" }
        end

        # Only cid should be included (it's a direct dependency)
        expect(member_deps.map(&:name)).to eq(["cid"])
      end

      it "correctly identifies workspace dependency versions" do
        wasmtime = dependencies.find { |d| d.name == "wasmtime" }
        expect(wasmtime).not_to be_nil
        expect(wasmtime.version).to eq("31.0.0")

        serde = dependencies.find { |d| d.name == "serde" }
        expect(serde).not_to be_nil
        expect(serde.version).to eq("1.0.164")
      end

      it "sets correct groups for workspace dependencies" do
        wasmtime = dependencies.find { |d| d.name == "wasmtime" }
        workspace_req = wasmtime.requirements.find { |r| r[:file] == "Cargo.toml" }

        expect(workspace_req[:groups]).to include("workspace.dependencies")
      end

      it "includes non-workspace dependencies from member manifests" do
        cid = dependencies.find { |d| d.name == "cid" }
        expect(cid).not_to be_nil
        expect(cid.version).to eq("0.11.1")
        expect(cid.requirements.first[:file]).to eq("fvm/Cargo.toml")
      end
    end
  end

  context "with mixed workspace and direct dependencies" do
    let(:mixed_toml) do
      <<~TOML
        [package]
        name = "mixed"
        version = "0.1.0"

        [dependencies]
        wasmtime = { workspace = true }
        serde = { workspace = true, features = ["derive", "rc"] }
        tokio = { version = "1.35.0", features = ["full"] }
      TOML
    end

    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "Cargo.toml",
          content: fixture("manifests", "workspace_dependencies", "Cargo.toml")
        ),
        Dependabot::DependencyFile.new(
          name: "mixed/Cargo.toml",
          content: mixed_toml
        )
      ]
    end

    it "includes direct dependencies but skips workspace references" do
      dependencies = parser.parse

      # Check that tokio (direct dep) is included
      tokio = dependencies.find { |d| d.name == "tokio" }
      expect(tokio).not_to be_nil

      # Check that wasmtime and serde from mixed/Cargo.toml are not included
      mixed_deps = dependencies.select do |dep|
        dep.requirements.any? { |r| r[:file] == "mixed/Cargo.toml" }
      end

      expect(mixed_deps.map(&:name)).to eq(["tokio"])
    end
  end
end
