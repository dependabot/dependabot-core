# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/update_checker"
require "dependabot/pre_commit/additional_dependency_checkers/conda"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers::Conda do
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
      language: "conda",
      hook_id: "conda-hook",
      hook_repo: "https://github.com/example/conda-pre-commit",
      package_name: "numpy",
      original_name: "numpy",
      original_string: "numpy=1.26.0",
      extras: nil
    }
  end

  let(:requirements) do
    [{
      requirement: "==1.26.0",
      groups: ["additional_dependencies"],
      file: ".pre-commit-config.yaml",
      source: source
    }]
  end

  let(:current_version) { "1.26.0" }

  describe "#latest_version" do
    let(:conda_checker_class) { class_double(Dependabot::Conda::UpdateChecker) }
    let(:conda_checker) { instance_double(Dependabot::UpdateCheckers::Base) }
    let(:latest_version_obj) { Dependabot::Conda::Version.new("1.27.0") }

    before do
      allow(Dependabot::UpdateCheckers).to receive(:for_package_manager)
        .with("conda")
        .and_return(conda_checker_class)
      allow(conda_checker_class).to receive(:new).and_return(conda_checker)
      allow(conda_checker).to receive(:latest_version).and_return(latest_version_obj)
    end

    it "delegates to conda UpdateChecker" do
      result = checker.latest_version
      expect(result).to eq("1.27.0")
    end

    it "creates a conda-compatible dependency" do
      expect(conda_checker_class).to receive(:new) do |args|
        dep = args[:dependency]
        expect(dep.name).to eq("numpy")
        expect(dep.version).to eq("1.26.0")
        expect(dep.package_manager).to eq("conda")
        conda_checker
      end

      checker.latest_version
    end

    it "builds a synthetic environment.yml" do
      expect(conda_checker_class).to receive(:new) do |args|
        files = args[:dependency_files]
        expect(files.length).to eq(1)
        expect(files.first.name).to eq("environment.yml")

        content = files.first.content
        expect(content).to include("numpy==1.26.0")
        conda_checker
      end

      checker.latest_version
    end

    context "when the conda registry is unreachable" do
      before do
        allow(conda_checker_class).to receive(:new).and_raise(Dependabot::RegistryError.new(503, "Connection failed"))
      end

      it "returns nil and logs the error" do
        expect(Dependabot.logger).to receive(:debug).with(/Error checking Conda package/)
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package doesn't exist" do
      before do
        allow(conda_checker).to receive(:latest_version).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package_name is missing from source" do
      let(:source) { { type: "additional_dependency", language: "conda" } }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    let(:latest_version) { "1.27.0" }

    context "with exact version constraint (==)" do
      let(:requirements) do
        [{
          requirement: "==1.26.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "updates the requirement with == operator" do
        updated = checker.updated_requirements(latest_version)
        expect(updated.first[:requirement]).to eq("==1.27.0")
        expect(updated.first[:source][:original_string]).to eq("numpy=1.27.0")
      end
    end

    context "with single = operator (conda style)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "conda",
          hook_id: "conda-hook",
          hook_repo: "https://github.com/example/conda-pre-commit",
          package_name: "pandas",
          original_name: "pandas",
          original_string: "pandas=2.0.0",
          extras: nil
        }
      end

      let(:requirements) do
        [{
          requirement: "=2.0.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the single = operator" do
        updated = checker.updated_requirements("2.1.0")
        expect(updated.first[:requirement]).to eq("=2.1.0")
        expect(updated.first[:source][:original_string]).to eq("pandas=2.1.0")
      end
    end

    context "with minimum version constraint (>=)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "conda",
          hook_id: "conda-hook",
          hook_repo: "https://github.com/example/conda-pre-commit",
          package_name: "scipy",
          original_name: "scipy",
          original_string: "scipy>=1.10.0",
          extras: nil
        }
      end

      let(:requirements) do
        [{
          requirement: ">=1.10.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "bumps the lower bound to the new version" do
        updated = checker.updated_requirements("1.12.0")
        expect(updated.first[:requirement]).to eq(">=1.12.0")
        expect(updated.first[:source][:original_string]).to eq("scipy>=1.12.0")
      end
    end

    context "with channel prefix" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "conda",
          hook_id: "conda-hook",
          hook_repo: "https://github.com/example/conda-pre-commit",
          package_name: "pytorch",
          original_name: "pytorch",
          original_string: "conda-forge::pytorch=2.0.0",
          extras: "conda-forge"
        }
      end

      let(:requirements) do
        [{
          requirement: "==2.0.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the channel prefix" do
        updated = checker.updated_requirements("2.1.0")
        expect(updated.first[:requirement]).to eq("==2.1.0")
        expect(updated.first[:source][:original_string]).to eq("conda-forge::pytorch=2.1.0")
      end
    end

    context "with no original requirement" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "conda",
          hook_id: "conda-hook",
          hook_repo: "https://github.com/example/conda-pre-commit",
          package_name: "matplotlib",
          original_name: "matplotlib",
          original_string: "matplotlib",
          extras: nil
        }
      end

      let(:requirements) do
        [{
          requirement: nil,
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "adds == operator for the new version" do
        updated = checker.updated_requirements("3.8.0")
        expect(updated.first[:requirement]).to eq("==3.8.0")
        expect(updated.first[:source][:original_string]).to eq("matplotlib=3.8.0")
      end
    end

    context "when source type is not additional_dependency" do
      let(:requirements) do
        [{
          requirement: "==1.26.0",
          groups: ["dependencies"],
          file: "environment.yml",
          source: { type: "default" }
        }]
      end

      it "returns the requirement unchanged" do
        updated = checker.updated_requirements(latest_version)
        expect(updated.first[:requirement]).to eq("==1.26.0")
      end
    end
  end
end
