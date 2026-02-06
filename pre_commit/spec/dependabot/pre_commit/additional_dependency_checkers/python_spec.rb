# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_checkers/python"
require "dependabot/python/update_checker"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers::Python do
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
      language: "python",
      hook_id: "mypy",
      repo_url: "https://github.com/pre-commit/mirrors-mypy",
      package_name: "types-requests",
      original_name: "types-requests",
      original_string: "types-requests==2.31.0.1"
    }
  end

  let(:requirements) do
    [{
      requirement: "==2.31.0.1",
      groups: ["additional_dependencies"],
      file: ".pre-commit-config.yaml",
      source: source
    }]
  end

  let(:current_version) { "2.31.0.1" }

  describe "#latest_version" do
    let(:pip_checker) { instance_double(Dependabot::Python::UpdateChecker) }
    let(:latest_version_obj) { Dependabot::Python::Version.new("2.31.0.10") }

    before do
      allow(Dependabot::Python::UpdateChecker).to receive(:new).and_return(pip_checker)
      allow(pip_checker).to receive(:latest_version).and_return(latest_version_obj)
    end

    it "delegates to Python::UpdateChecker" do
      expect(Dependabot::Python::UpdateChecker).to receive(:new).with(
        hash_including(
          dependency: an_instance_of(Dependabot::Dependency),
          dependency_files: [],
          credentials: credentials,
          ignored_versions: [],
          security_advisories: [],
          raise_on_ignored: false
        )
      ).and_return(pip_checker)

      result = checker.latest_version
      expect(result).to eq("2.31.0.10")
    end

    it "creates a pip-compatible dependency" do
      expect(Dependabot::Python::UpdateChecker).to receive(:new) do |args|
        dep = args[:dependency]
        expect(dep.name).to eq("types-requests")
        expect(dep.version).to eq("2.31.0.1")
        expect(dep.package_manager).to eq("pip")
        expect(dep.requirements.first[:requirement]).to eq("==2.31.0.1")
        pip_checker
      end

      checker.latest_version
    end

    context "when PyPI is unreachable" do
      before do
        allow(Dependabot::Python::UpdateChecker).to receive(:new).and_raise(StandardError, "Connection failed")
      end

      it "returns nil and logs the error" do
        expect(Dependabot.logger).to receive(:debug).with(/Error checking Python package/)
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package doesn't exist" do
      before do
        allow(pip_checker).to receive(:latest_version).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package_name is missing from source" do
      let(:source) { { type: "additional_dependency", language: "python" } }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    let(:latest_version) { "2.31.0.10" }

    context "with exact version constraint (==)" do
      let(:requirements) do
        [{
          requirement: "==2.31.0.1",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "updates the requirement with == operator" do
        updated = checker.updated_requirements(latest_version)
        expect(updated.first[:requirement]).to eq("==2.31.0.10")
        expect(updated.first[:source][:original_string]).to eq("types-requests==2.31.0.10")
      end
    end

    context "with minimum version constraint (>=)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "python",
          hook_id: "mypy",
          repo_url: "https://github.com/pre-commit/mirrors-mypy",
          package_name: "flake8",
          original_name: "flake8",
          original_string: "flake8>=5.0.0"
        }
      end

      let(:requirements) do
        [{
          requirement: ">=5.0.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the >= operator" do
        updated = checker.updated_requirements("6.0.0")
        expect(updated.first[:requirement]).to eq(">=6.0.0")
        expect(updated.first[:source][:original_string]).to eq("flake8>=6.0.0")
      end
    end

    context "with compatible release constraint (~=)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "python",
          hook_id: "mypy",
          repo_url: "https://github.com/pre-commit/mirrors-mypy",
          package_name: "pytest",
          original_name: "pytest",
          original_string: "pytest~=7.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "~=7.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ~= operator" do
        updated = checker.updated_requirements("7.4.0")
        expect(updated.first[:requirement]).to eq("~=7.4.0")
        expect(updated.first[:source][:original_string]).to eq("pytest~=7.4.0")
      end
    end

    context "with extras in package name" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "python",
          hook_id: "black",
          repo_url: "https://github.com/psf/black",
          package_name: "black",
          original_name: "black[d]",
          original_string: "black[d]>=23.0.0"
        }
      end

      let(:requirements) do
        [{
          requirement: ">=23.0.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves extras in the updated original_string" do
        updated = checker.updated_requirements("24.0.0")
        expect(updated.first[:requirement]).to eq(">=24.0.0")
        expect(updated.first[:source][:original_string]).to eq("black[d]>=24.0.0")
      end
    end

    context "with multiple extras" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "python",
          hook_id: "test",
          repo_url: "https://github.com/test/test",
          package_name: "httpx",
          original_name: "httpx[http2,cli]",
          original_string: "httpx[http2,cli]>=0.24.0"
        }
      end

      let(:requirements) do
        [{
          requirement: ">=0.24.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves all extras in the updated original_string" do
        updated = checker.updated_requirements("0.25.0")
        expect(updated.first[:requirement]).to eq(">=0.25.0")
        expect(updated.first[:source][:original_string]).to eq("httpx[http2,cli]>=0.25.0")
      end
    end

    context "with other operators" do
      {
        "<=" => "<=",
        ">" => ">",
        "<" => "<",
        "!=" => "!=",
        "===" => "==="
      }.each do |operator, expected_operator|
        context "with #{operator} operator" do
          let(:requirements) do
            [{
              requirement: "#{operator}2.31.0.1",
              groups: ["additional_dependencies"],
              file: ".pre-commit-config.yaml",
              source: source
            }]
          end

          it "preserves the #{operator} operator" do
            updated = checker.updated_requirements("2.32.0")
            expect(updated.first[:requirement]).to eq("#{expected_operator}2.32.0")
          end
        end
      end
    end

    context "with no operator in requirement (defaults to ==)" do
      let(:requirements) do
        [{
          requirement: "2.31.0.1",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "defaults to == operator" do
        updated = checker.updated_requirements("2.31.0.10")
        expect(updated.first[:requirement]).to eq("==2.31.0.10")
      end
    end

    it "preserves all requirement properties" do
      updated = checker.updated_requirements(latest_version)
      expect(updated.first[:groups]).to eq(["additional_dependencies"])
      expect(updated.first[:file]).to eq(".pre-commit-config.yaml")
      expect(updated.first[:source][:type]).to eq("additional_dependency")
      expect(updated.first[:source][:language]).to eq("python")
      expect(updated.first[:source][:hook_id]).to eq("mypy")
      expect(updated.first[:source][:repo_url]).to eq("https://github.com/pre-commit/mirrors-mypy")
      expect(updated.first[:source][:package_name]).to eq("types-requests")
    end
  end
end
