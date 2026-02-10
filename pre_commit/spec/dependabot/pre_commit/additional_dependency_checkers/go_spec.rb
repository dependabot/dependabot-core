# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_checkers/go"
require "dependabot/go_modules/update_checker"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers::Go do
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
      language: "golang",
      hook_id: "golangci-lint",
      hook_repo: "https://github.com/golangci/golangci-lint",
      package_name: "golang.org/x/tools",
      original_name: "golang.org/x/tools",
      original_string: "golang.org/x/tools@v0.28.0"
    }
  end

  let(:requirements) do
    [{
      requirement: "v0.28.0",
      groups: ["additional_dependencies"],
      file: ".pre-commit-config.yaml",
      source: source
    }]
  end

  let(:current_version) { "0.28.0" }

  describe "#latest_version" do
    let(:go_checker) { instance_double(Dependabot::GoModules::UpdateChecker) }
    let(:latest_version_obj) { Dependabot::GoModules::Version.new("0.29.0") }

    before do
      allow(Dependabot::GoModules::UpdateChecker).to receive(:new).and_return(go_checker)
      allow(go_checker).to receive(:latest_version).and_return(latest_version_obj)
    end

    it "delegates to GoModules::UpdateChecker" do
      result = checker.latest_version
      expect(result).to eq("0.29.0")
    end

    it "creates a go_modules-compatible dependency" do
      expect(Dependabot::GoModules::UpdateChecker).to receive(:new) do |args|
        dep = args[:dependency]
        expect(dep.name).to eq("golang.org/x/tools")
        expect(dep.version).to eq("0.28.0")
        expect(dep.package_manager).to eq("go_modules")
        expect(dep.requirements.first[:requirement]).to eq("v0.28.0")
        expect(dep.requirements.first[:file]).to eq("go.mod")
        expect(dep.requirements.first[:source]).to eq({ type: "default", source: "golang.org/x/tools" })
        go_checker
      end

      checker.latest_version
    end

    it "creates synthetic go.mod dependency files" do
      expect(Dependabot::GoModules::UpdateChecker).to receive(:new) do |args|
        files = args[:dependency_files]
        expect(files.length).to eq(1)
        expect(files.first.name).to eq("go.mod")
        expect(files.first.content).to include("module dependabot/pre-commit-dummy")
        expect(files.first.content).to include("require golang.org/x/tools v0.28.0")
        go_checker
      end

      checker.latest_version
    end

    context "when Go proxy is unreachable" do
      before do
        allow(Dependabot::GoModules::UpdateChecker).to receive(:new).and_raise(
          Excon::Error::Timeout, "Connection timed out"
        )
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when module doesn't exist" do
      before do
        allow(go_checker).to receive(:latest_version).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package_name is missing from source" do
      let(:source) { { type: "additional_dependency", language: "golang" } }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when current_version is nil but requirement has version" do
      let(:current_version) { nil }

      it "extracts version from requirement" do
        expect(Dependabot::GoModules::UpdateChecker).to receive(:new) do |args|
          dep = args[:dependency]
          expect(dep.version).to eq("0.28.0")
          go_checker
        end

        checker.latest_version
      end
    end

    context "when a DependencyNotFound error occurs" do
      before do
        allow(Dependabot::GoModules::UpdateChecker).to receive(:new).and_raise(
          Dependabot::DependencyNotFound, "golang.org/x/nonexistent"
        )
      end

      it "returns nil and logs the error" do
        expect(Dependabot.logger).to receive(:warn).with(/Error checking Go module/)
        expect(checker.latest_version).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    context "with a standard semver version" do
      let(:latest_version) { "0.29.0" }

      it "updates the requirement with v prefix" do
        updated = checker.updated_requirements(latest_version)
        expect(updated.first[:requirement]).to eq("v0.29.0")
      end

      it "updates the original_string in source" do
        updated = checker.updated_requirements(latest_version)
        expect(updated.first[:source][:original_string]).to eq("golang.org/x/tools@v0.29.0")
      end
    end

    context "with a major version bump" do
      let(:latest_version) { "1.0.0" }

      it "updates the requirement" do
        updated = checker.updated_requirements(latest_version)
        expect(updated.first[:requirement]).to eq("v1.0.0")
        expect(updated.first[:source][:original_string]).to eq("golang.org/x/tools@v1.0.0")
      end
    end

    context "with a patch-level update" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "golang",
          hook_id: "golangci-lint",
          hook_repo: "https://github.com/golangci/golangci-lint",
          package_name: "github.com/stretchr/testify",
          original_name: "github.com/stretchr/testify",
          original_string: "github.com/stretchr/testify@v1.9.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "v1.9.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "updates to the new patch version" do
        updated = checker.updated_requirements("1.9.1")
        expect(updated.first[:requirement]).to eq("v1.9.1")
        expect(updated.first[:source][:original_string]).to eq("github.com/stretchr/testify@v1.9.1")
      end
    end

    context "when source type is not additional_dependency" do
      let(:requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".pre-commit-config.yaml",
          source: { type: "git", url: "https://github.com/some/repo" }
        }]
      end

      it "returns the requirement unchanged" do
        updated = checker.updated_requirements("0.29.0")
        expect(updated.first).to eq(requirements.first)
      end
    end

    it "preserves all requirement properties" do
      updated = checker.updated_requirements("0.29.0")
      expect(updated.first[:groups]).to eq(["additional_dependencies"])
      expect(updated.first[:file]).to eq(".pre-commit-config.yaml")
      expect(updated.first[:source][:type]).to eq("additional_dependency")
      expect(updated.first[:source][:language]).to eq("golang")
      expect(updated.first[:source][:hook_id]).to eq("golangci-lint")
      expect(updated.first[:source][:hook_repo]).to eq("https://github.com/golangci/golangci-lint")
      expect(updated.first[:source][:package_name]).to eq("golang.org/x/tools")
    end

    context "when original_name is missing (falls back to package_name)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "golang",
          hook_id: "golangci-lint",
          hook_repo: "https://github.com/golangci/golangci-lint",
          package_name: "golang.org/x/tools",
          original_string: "golang.org/x/tools@v0.28.0"
        }
      end

      it "uses package_name for the original_string" do
        updated = checker.updated_requirements("0.29.0")
        expect(updated.first[:source][:original_string]).to eq("golang.org/x/tools@v0.29.0")
      end
    end
  end
end
