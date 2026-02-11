# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/update_checker"
require "dependabot/julia/registry_client"
require "dependabot/pre_commit/additional_dependency_checkers/julia"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers::Julia do
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
      language: "julia",
      hook_id: "julia-lint",
      hook_repo: "https://github.com/example/julia-lint",
      package_name: "JSON",
      original_name: "JSON",
      original_string: "JSON@0.21.4"
    }
  end

  let(:requirements) do
    [{
      requirement: "0.21.4",
      groups: ["additional_dependencies"],
      file: ".pre-commit-config.yaml",
      source: source
    }]
  end

  let(:current_version) { "0.21.4" }

  let(:registry_client) { instance_double(Dependabot::Julia::RegistryClient) }
  let(:resolved_uuid) { "682c06a0-de6a-54ab-a142-c8b1cf79cde6" }

  before do
    allow(Dependabot::Julia::RegistryClient).to receive(:new).and_return(registry_client)
    allow(registry_client).to receive(:resolve_package_uuid).and_return(resolved_uuid)
  end

  describe "#latest_version" do
    let(:julia_checker_class) { class_double(Dependabot::Julia::UpdateChecker) }
    let(:julia_checker) { instance_double(Dependabot::UpdateCheckers::Base) }
    let(:latest_version_obj) { Gem::Version.new("0.22.0") }

    before do
      allow(Dependabot::UpdateCheckers).to receive(:for_package_manager)
        .with("julia")
        .and_return(julia_checker_class)
      allow(julia_checker_class).to receive(:new).and_return(julia_checker)
      allow(julia_checker).to receive(:latest_version).and_return(latest_version_obj)
    end

    it "delegates to Julia UpdateChecker" do
      result = checker.latest_version
      expect(result).to eq("0.22.0")
    end

    it "creates a julia-compatible dependency" do
      expect(julia_checker_class).to receive(:new) do |args|
        dep = args[:dependency]
        expect(dep.name).to eq("JSON")
        expect(dep.package_manager).to eq("julia")
        expect(dep.metadata[:julia_uuid]).to eq(resolved_uuid)
        julia_checker
      end

      checker.latest_version
    end

    it "builds a synthetic Project.toml with resolved UUID" do
      expect(julia_checker_class).to receive(:new) do |args|
        files = args[:dependency_files]
        expect(files.length).to eq(1)
        expect(files.first.name).to eq("Project.toml")
        expect(files.first.content).to include("JSON")
        expect(files.first.content).to include("[deps]")
        expect(files.first.content).to include("[compat]")
        expect(files.first.content).to include(resolved_uuid)
        julia_checker
      end

      checker.latest_version
    end

    context "when the registry is unreachable" do
      before do
        allow(registry_client).to receive(:resolve_package_uuid).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when the package doesn't exist" do
      before do
        allow(julia_checker).to receive(:latest_version).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package_name is missing from source" do
      let(:source) { { type: "additional_dependency", language: "julia" } }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    context "with exact version (no operator)" do
      it "updates to the new exact version" do
        updated = checker.updated_requirements("0.22.0")
        expect(updated.first[:requirement]).to eq("0.22.0")
        expect(updated.first[:source][:original_string]).to eq("JSON@0.22.0")
      end
    end

    context "with caret range (^)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "julia",
          hook_id: "julia-format",
          hook_repo: "https://github.com/example/julia-format",
          package_name: "JuliaFormatter",
          original_name: "JuliaFormatter",
          original_string: "JuliaFormatter@^1.0.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "^1.0.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ^ operator" do
        updated = checker.updated_requirements("1.1.0")
        expect(updated.first[:requirement]).to eq("^1.1.0")
        expect(updated.first[:source][:original_string]).to eq("JuliaFormatter@^1.1.0")
      end
    end

    context "with tilde range (~)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "julia",
          hook_id: "julia-format",
          hook_repo: "https://github.com/example/julia-format",
          package_name: "CSTParser",
          original_name: "CSTParser",
          original_string: "CSTParser@~3.3.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "~3.3.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ~ operator" do
        updated = checker.updated_requirements("3.4.0")
        expect(updated.first[:requirement]).to eq("~3.4.0")
        expect(updated.first[:source][:original_string]).to eq("CSTParser@~3.4.0")
      end
    end

    it "preserves all requirement properties" do
      updated = checker.updated_requirements("0.22.0")
      expect(updated.first[:groups]).to eq(["additional_dependencies"])
      expect(updated.first[:file]).to eq(".pre-commit-config.yaml")
      expect(updated.first[:source][:type]).to eq("additional_dependency")
      expect(updated.first[:source][:language]).to eq("julia")
      expect(updated.first[:source][:hook_id]).to eq("julia-lint")
      expect(updated.first[:source][:hook_repo]).to eq("https://github.com/example/julia-lint")
      expect(updated.first[:source][:package_name]).to eq("JSON")
    end
  end
end
