# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/update_checker"
require "dependabot/pre_commit/additional_dependency_checkers/rust"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers::Rust do
  let(:checker) do
    described_class.new(
      source: source,
      credentials: credentials,
      requirements: requirements,
      current_version: current_version
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:source) do
    {
      type: "additional_dependency",
      language: "rust",
      hook_id: "nickel-lint",
      hook_repo: "https://github.com/nickel-org/rust-nickel",
      package_name: "serde",
      original_name: "serde",
      original_string: "serde:1.0.193"
    }
  end

  let(:requirements) do
    [{
      requirement: "1.0.193",
      groups: ["additional_dependencies"],
      file: ".pre-commit-config.yaml",
      source: source
    }]
  end

  let(:current_version) { "1.0.193" }

  describe "#latest_version" do
    let(:cargo_checker_class) { class_double(Dependabot::Cargo::UpdateChecker) }
    let(:cargo_checker) { instance_double(Dependabot::UpdateCheckers::Base) }
    let(:latest_version_obj) { Gem::Version.new("1.0.200") }

    before do
      allow(Dependabot::UpdateCheckers).to receive(:for_package_manager)
        .with("cargo")
        .and_return(cargo_checker_class)
      allow(cargo_checker_class).to receive(:new).and_return(cargo_checker)
      allow(cargo_checker).to receive(:latest_version).and_return(latest_version_obj)
    end

    it "delegates to cargo UpdateChecker" do
      result = checker.latest_version
      expect(result).to eq("1.0.200")
    end

    it "creates a cargo-compatible dependency" do
      expect(cargo_checker_class).to receive(:new) do |args|
        dep = args[:dependency]
        expect(dep.name).to eq("serde")
        expect(dep.version).to eq("1.0.193")
        expect(dep.package_manager).to eq("cargo")
        cargo_checker
      end

      checker.latest_version
    end

    it "builds a synthetic Cargo.toml" do
      expect(cargo_checker_class).to receive(:new) do |args|
        files = args[:dependency_files]
        expect(files.length).to eq(1)
        expect(files.first.name).to eq("Cargo.toml")
        expect(files.first.content).to include('serde = "=1.0.193"')
        cargo_checker
      end

      checker.latest_version
    end

    context "when the crates.io registry is unreachable" do
      before do
        allow(cargo_checker_class).to receive(:new).and_raise(Dependabot::RegistryError.new(503, "Connection failed"))
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when the package doesn't exist" do
      before do
        allow(cargo_checker).to receive(:latest_version).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package_name is missing from source" do
      let(:source) { { type: "additional_dependency", language: "rust" } }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    context "with exact version (no operator)" do
      it "updates to the new exact version" do
        updated = checker.updated_requirements("1.0.200")
        expect(updated.first[:requirement]).to eq("1.0.200")
        expect(updated.first[:source][:original_string]).to eq("serde:1.0.200")
      end
    end

    context "with a CLI dependency" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "rust",
          hook_id: "cargo-fmt",
          hook_repo: "https://github.com/example/rust-cli-hooks",
          package_name: "rustfmt-nightly",
          original_name: "rustfmt-nightly",
          extras: "cli",
          original_string: "cli:rustfmt-nightly:1.6.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "1.6.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      let(:current_version) { "1.6.0" }

      it "preserves the cli: prefix in the original_string" do
        updated = checker.updated_requirements("1.7.0")
        expect(updated.first[:requirement]).to eq("1.7.0")
        expect(updated.first[:source][:original_string]).to eq("cli:rustfmt-nightly:1.7.0")
      end
    end

    context "with caret range (^)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "rust",
          hook_id: "rust-lint",
          hook_repo: "https://github.com/example/rust-tilde-hooks",
          package_name: "clap",
          original_name: "clap",
          original_string: "clap:^4.4.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "^4.4.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ^ operator" do
        updated = checker.updated_requirements("4.5.0")
        expect(updated.first[:requirement]).to eq("^4.5.0")
        expect(updated.first[:source][:original_string]).to eq("clap:^4.5.0")
      end
    end

    context "with tilde range (~)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "rust",
          hook_id: "rust-lint",
          hook_repo: "https://github.com/example/rust-tilde-hooks",
          package_name: "anyhow",
          original_name: "anyhow",
          original_string: "anyhow:~1.0.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "~1.0.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ~ operator" do
        updated = checker.updated_requirements("1.1.0")
        expect(updated.first[:requirement]).to eq("~1.1.0")
        expect(updated.first[:source][:original_string]).to eq("anyhow:~1.1.0")
      end
    end

    it "preserves all requirement properties" do
      updated = checker.updated_requirements("1.0.200")
      expect(updated.first[:groups]).to eq(["additional_dependencies"])
      expect(updated.first[:file]).to eq(".pre-commit-config.yaml")
      expect(updated.first[:source][:type]).to eq("additional_dependency")
      expect(updated.first[:source][:language]).to eq("rust")
      expect(updated.first[:source][:hook_id]).to eq("nickel-lint")
      expect(updated.first[:source][:hook_repo]).to eq("https://github.com/nickel-org/rust-nickel")
      expect(updated.first[:source][:package_name]).to eq("serde")
    end
  end
end
