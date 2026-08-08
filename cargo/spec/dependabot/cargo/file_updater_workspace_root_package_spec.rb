# typed: false
# frozen_string_literal: true

require "toml-rb"

require "spec_helper"
require "dependabot/cargo/file_updater"
require "dependabot/dependency"
require "dependabot/dependency_file"

# A workspace root manifest can also be a package in its own right: `[workspace]` and
# `[workspace.dependencies]` alongside `[package]` and its own `[dependencies]`.
# Requirements in both sets have to be updated.
RSpec.describe Dependabot::Cargo::FileUpdater do
  let(:updater) do
    described_class.new(dependency_files: files, dependencies: dependencies, credentials: [])
  end

  let(:files) do
    [
      Dependabot::DependencyFile.new(name: "Cargo.toml", content: root_manifest),
      Dependabot::DependencyFile.new(name: "sdk/Cargo.toml", content: member_manifest)
    ]
  end

  let(:member_manifest) do
    <<~TOML
      [package]
      name = "sdk"
      version = "0.1.0"

      [dependencies]
      serde = { workspace = true }
      wasmtime = "31.0.0"
    TOML
  end

  let(:updated_root) { updater.updated_dependency_files.find { |f| f.name == "Cargo.toml" }.content }
  let(:updated_member) { updater.updated_dependency_files.find { |f| f.name == "sdk/Cargo.toml" }.content }

  def dependency(name:, version:, previous_version:, requirements:, previous_requirements:)
    Dependabot::Dependency.new(
      name: name,
      version: version,
      previous_version: previous_version,
      package_manager: "cargo",
      requirements: requirements,
      previous_requirements: previous_requirements
    )
  end

  def req(file:, requirement:, groups:)
    { file: file, requirement: requirement, groups: groups, source: nil }
  end

  context "when a crate is declared in the root package's own [dependencies]" do
    let(:root_manifest) do
      <<~TOML
        [workspace]
        members = [".", "sdk"]

        [workspace.dependencies]
        serde = { version = "1.0.164", features = ["derive"] }

        [package]
        name = "root"
        version = "0.1.0"

        [dependencies]
        serde = { workspace = true }
        wasmtime = "31.0.0"
      TOML
    end

    let(:dependencies) do
      [dependency(
        name: "wasmtime",
        version: "35.0.0",
        previous_version: "31.0.0",
        requirements: [req(file: "Cargo.toml", requirement: "35.0.0", groups: ["dependencies"]),
                       req(file: "sdk/Cargo.toml", requirement: "35.0.0", groups: ["dependencies"])],
        previous_requirements: [req(file: "Cargo.toml", requirement: "31.0.0", groups: ["dependencies"]),
                                req(file: "sdk/Cargo.toml", requirement: "31.0.0", groups: ["dependencies"])]
      )]
    end

    it "updates the root package's requirement" do
      expect(TomlRB.parse(updated_root).dig("dependencies", "wasmtime")).to eq("35.0.0")
    end

    it "updates the member's requirement to the same version" do
      # Updating members but not the root is what resolves to two versions of one crate.
      expect(TomlRB.parse(updated_member).dig("dependencies", "wasmtime")).to eq("35.0.0")
    end
  end

  context "when a crate is declared only in the root package" do
    let(:root_manifest) do
      <<~TOML
        [workspace]
        members = [".", "sdk"]

        [workspace.dependencies]
        serde = { version = "1.0.164", features = ["derive"] }

        [package]
        name = "root"
        version = "0.1.0"

        [dependencies]
        clap = "4.6.1"
      TOML
    end

    let(:dependencies) do
      [dependency(
        name: "clap",
        version: "4.6.2",
        previous_version: "4.6.1",
        requirements: [req(file: "Cargo.toml", requirement: "4.6.2", groups: ["dependencies"])],
        previous_requirements: [req(file: "Cargo.toml", requirement: "4.6.1", groups: ["dependencies"])]
      )]
    end

    it "updates it rather than silently reporting an update it did not make" do
      expect(TomlRB.parse(updated_root).dig("dependencies", "clap")).to eq("4.6.2")
    end
  end

  context "when a crate is declared in [workspace.dependencies]" do
    let(:root_manifest) do
      <<~TOML
        [workspace]
        members = [".", "sdk"]

        [workspace.dependencies]
        serde = { version = "1.0.164", features = ["derive"] }

        [package]
        name = "root"
        version = "0.1.0"

        [dependencies]
        serde = { workspace = true }
      TOML
    end

    let(:dependencies) do
      [dependency(
        name: "serde",
        version: "1.0.200",
        previous_version: "1.0.164",
        requirements: [req(file: "Cargo.toml", requirement: "1.0.200", groups: ["workspace.dependencies"])],
        previous_requirements: [req(file: "Cargo.toml", requirement: "1.0.164", groups: ["workspace.dependencies"])]
      )]
    end

    it "still updates the workspace table" do
      expect(TomlRB.parse(updated_root).dig("workspace", "dependencies", "serde", "version")).to eq("1.0.200")
    end

    it "leaves the inherited declaration alone" do
      expect(TomlRB.parse(updated_root).dig("dependencies", "serde")).to eq("workspace" => true)
    end
  end

  context "when the same crate is in [workspace.dependencies] and the root package" do
    let(:root_manifest) do
      <<~TOML
        [workspace]
        members = [".", "sdk"]

        [workspace.dependencies]
        wasmtime = "31.0.0"

        [package]
        name = "root"
        version = "0.1.0"

        [dependencies]
        wasmtime = "31.0.0"
      TOML
    end

    let(:dependencies) do
      [dependency(
        name: "wasmtime",
        version: "35.0.0",
        previous_version: "31.0.0",
        requirements: [req(file: "Cargo.toml", requirement: "35.0.0", groups: ["workspace.dependencies"]),
                       req(file: "Cargo.toml", requirement: "35.0.0", groups: ["dependencies"])],
        previous_requirements: [req(file: "Cargo.toml", requirement: "31.0.0", groups: ["workspace.dependencies"]),
                                req(file: "Cargo.toml", requirement: "31.0.0", groups: ["dependencies"])]
      )]
    end

    it "updates both tables" do
      parsed = TomlRB.parse(updated_root)
      expect(parsed.dig("workspace", "dependencies", "wasmtime")).to eq("35.0.0")
      expect(parsed.dig("dependencies", "wasmtime")).to eq("35.0.0")
    end
  end

  context "when both tables use table-header notation" do
    # Regression test: the workspace table is rewritten first, and ManifestUpdater's
    # table-header matcher is unanchored, so it re-matches the already-updated
    # [workspace.dependencies.serde] and finds nothing left to change.
    let(:root_manifest) do
      <<~TOML
        [workspace]
        members = [".", "sdk"]

        [workspace.dependencies.serde]
        version = "1.0.164"
        features = ["derive"]

        [package]
        name = "root"
        version = "0.1.0"

        [dependencies.serde]
        version = "1.0.164"
        features = ["derive"]
      TOML
    end

    let(:dependencies) do
      [dependency(
        name: "serde",
        version: "1.0.200",
        previous_version: "1.0.164",
        requirements: [req(file: "Cargo.toml", requirement: "1.0.200", groups: ["workspace.dependencies"]),
                       req(file: "Cargo.toml", requirement: "1.0.200", groups: ["dependencies"])],
        previous_requirements: [req(file: "Cargo.toml", requirement: "1.0.164", groups: ["workspace.dependencies"]),
                                req(file: "Cargo.toml", requirement: "1.0.164", groups: ["dependencies"])]
      )]
    end

    it "updates the workspace table" do
      expect(TomlRB.parse(updated_root).dig("workspace", "dependencies", "serde", "version")).to eq("1.0.200")
    end

    it "updates the root package's table too" do
      expect(TomlRB.parse(updated_root).dig("dependencies", "serde", "version")).to eq("1.0.200")
    end

    it "preserves the rest of the declaration" do
      expect(TomlRB.parse(updated_root).dig("dependencies", "serde", "features")).to eq(["derive"])
    end
  end

  context "when one dependency cannot be updated but another can" do
    # The updater is deliberately made to fail for serde, to prove one failure does not
    # discard another dependency's update and that the job still produces a pull request.
    let(:root_manifest) do
      <<~TOML
        [workspace]
        members = [".", "sdk"]

        [workspace.dependencies]
        serde = "1.0.164"

        [package]
        name = "root"
        version = "0.1.0"

        [dependencies]
        clap = "4.6.1"
        serde = "1.0.164"
      TOML
    end

    let(:dependencies) do
      [
        dependency(
          name: "clap",
          version: "4.6.2",
          previous_version: "4.6.1",
          requirements: [req(file: "Cargo.toml", requirement: "4.6.2", groups: ["dependencies"])],
          previous_requirements: [req(file: "Cargo.toml", requirement: "4.6.1", groups: ["dependencies"])]
        ),
        dependency(
          name: "serde",
          version: "1.0.200",
          previous_version: "1.0.164",
          requirements: [req(file: "Cargo.toml", requirement: "1.0.200", groups: ["dependencies"])],
          previous_requirements: [req(file: "Cargo.toml", requirement: "1.0.164", groups: ["dependencies"])]
        )
      ]
    end

    before do
      allow(Dependabot.logger).to receive(:warn)
      original = Dependabot::Cargo::FileUpdater::ManifestUpdater.method(:new)
      allow(Dependabot::Cargo::FileUpdater::ManifestUpdater).to receive(:new) do |**kwargs|
        if kwargs[:dependencies].map(&:name) == ["serde"]
          instance_double(
            Dependabot::Cargo::FileUpdater::ManifestUpdater,
            updated_manifest_content: nil
          ).tap do |double|
            allow(double).to receive(:updated_manifest_content)
              .and_raise(Dependabot::DependencyFileContentNotChanged)
          end
        else
          original.call(**kwargs)
        end
      end
    end

    it "still applies the update it can" do
      expect(TomlRB.parse(updated_root).dig("dependencies", "clap")).to eq("4.6.2")
    end

    it "logs the dependency it could not update" do
      updated_root
      expect(Dependabot.logger).to have_received(:warn).with(/could not update serde/)
    end
  end

  context "when the root package has no changed requirements of its own" do
    let(:root_manifest) do
      <<~TOML
        [workspace]
        members = [".", "sdk"]

        [workspace.dependencies]
        serde = { version = "1.0.164", features = ["derive"] }

        [package]
        name = "root"
        version = "0.1.0"

        [dependencies]
        serde = { workspace = true }
      TOML
    end

    let(:dependencies) do
      [dependency(
        name: "wasmtime",
        version: "35.0.0",
        previous_version: "31.0.0",
        requirements: [req(file: "sdk/Cargo.toml", requirement: "35.0.0", groups: ["dependencies"])],
        previous_requirements: [req(file: "sdk/Cargo.toml", requirement: "31.0.0", groups: ["dependencies"])]
      )]
    end

    it "leaves the root manifest untouched" do
      expect(updater.updated_dependency_files.map(&:name)).to eq(["sdk/Cargo.toml"])
    end
  end
end
