# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_checkers/node"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers::Node do
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
      language: "node",
      hook_id: "eslint",
      hook_repo: "https://github.com/pre-commit/mirrors-eslint",
      package_name: "eslint",
      original_name: "eslint",
      original_string: "eslint@4.15.0"
    }
  end

  let(:requirements) do
    [{
      requirement: "4.15.0",
      groups: ["additional_dependencies"],
      file: ".pre-commit-config.yaml",
      source: source
    }]
  end

  let(:current_version) { "4.15.0" }

  describe "#latest_version" do
    # rubocop:disable RSpec/VerifiedDoubleReference
    let(:npm_checker_class) { class_double("Dependabot::NpmAndYarn::UpdateChecker") }
    # rubocop:enable RSpec/VerifiedDoubleReference
    let(:npm_checker) { instance_double(Dependabot::UpdateCheckers::Base) }
    let(:latest_version_obj) { Gem::Version.new("9.0.0") }

    before do
      allow(Dependabot::UpdateCheckers).to receive(:for_package_manager)
        .with("npm_and_yarn")
        .and_return(npm_checker_class)
      allow(npm_checker_class).to receive(:new).and_return(npm_checker)
      allow(npm_checker).to receive(:latest_version).and_return(latest_version_obj)
    end

    it "delegates to npm_and_yarn UpdateChecker" do
      result = checker.latest_version
      expect(result).to eq("9.0.0")
    end

    it "creates an npm-compatible dependency" do
      expect(npm_checker_class).to receive(:new) do |args|
        dep = args[:dependency]
        expect(dep.name).to eq("eslint")
        expect(dep.version).to eq("4.15.0")
        expect(dep.package_manager).to eq("npm_and_yarn")
        npm_checker
      end

      checker.latest_version
    end

    it "builds a synthetic package.json" do
      expect(npm_checker_class).to receive(:new) do |args|
        files = args[:dependency_files]
        expect(files.length).to eq(1)
        expect(files.first.name).to eq("package.json")

        content = JSON.parse(files.first.content)
        expect(content["dependencies"]["eslint"]).to eq("4.15.0")
        npm_checker
      end

      checker.latest_version
    end

    context "when the npm registry is unreachable" do
      before do
        allow(npm_checker_class).to receive(:new).and_raise(StandardError, "Connection failed")
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when the package doesn't exist" do
      before do
        allow(npm_checker).to receive(:latest_version).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package_name is missing from source" do
      let(:source) { { type: "additional_dependency", language: "node" } }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "with a scoped package" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "node",
          hook_id: "prettier",
          hook_repo: "https://github.com/pre-commit/mirrors-prettier",
          package_name: "@prettier/plugin-xml",
          original_name: "@prettier/plugin-xml",
          original_string: "@prettier/plugin-xml@3.2.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "3.2.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      let(:current_version) { "3.2.0" }

      it "passes the scoped package name to the npm checker" do
        expect(npm_checker_class).to receive(:new) do |args|
          dep = args[:dependency]
          expect(dep.name).to eq("@prettier/plugin-xml")
          npm_checker
        end

        checker.latest_version
      end
    end
  end

  describe "#updated_requirements" do
    context "with exact version (no operator)" do
      let(:requirements) do
        [{
          requirement: "4.15.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "updates to the new exact version" do
        updated = checker.updated_requirements("9.0.0")
        expect(updated.first[:requirement]).to eq("9.0.0")
        expect(updated.first[:source][:original_string]).to eq("eslint@9.0.0")
      end
    end

    context "with caret range (^)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "node",
          hook_id: "lint",
          hook_repo: "https://github.com/example/hooks",
          package_name: "ts-node",
          original_name: "ts-node",
          original_string: "ts-node@^10.9.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "^10.9.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ^ operator" do
        updated = checker.updated_requirements("10.10.0")
        expect(updated.first[:requirement]).to eq("^10.10.0")
        expect(updated.first[:source][:original_string]).to eq("ts-node@^10.10.0")
      end
    end

    context "with tilde range (~)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "node",
          hook_id: "lint",
          hook_repo: "https://github.com/example/hooks",
          package_name: "typescript",
          original_name: "typescript",
          original_string: "typescript@~5.3.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "~5.3.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ~ operator" do
        updated = checker.updated_requirements("5.4.0")
        expect(updated.first[:requirement]).to eq("~5.4.0")
        expect(updated.first[:source][:original_string]).to eq("typescript@~5.4.0")
      end
    end

    context "with >= operator" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "node",
          hook_id: "eslint",
          hook_repo: "https://github.com/pre-commit/mirrors-eslint",
          package_name: "eslint",
          original_name: "eslint",
          original_string: "eslint@>=4.0.0"
        }
      end

      let(:requirements) do
        [{
          requirement: ">=4.0.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the >= operator" do
        updated = checker.updated_requirements("9.0.0")
        expect(updated.first[:requirement]).to eq(">=9.0.0")
        expect(updated.first[:source][:original_string]).to eq("eslint@>=9.0.0")
      end
    end

    context "with a scoped package" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "node",
          hook_id: "prettier",
          hook_repo: "https://github.com/pre-commit/mirrors-prettier",
          package_name: "@prettier/plugin-xml",
          original_name: "@prettier/plugin-xml",
          original_string: "@prettier/plugin-xml@3.2.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "3.2.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "correctly formats the scoped package update" do
        updated = checker.updated_requirements("3.3.0")
        expect(updated.first[:requirement]).to eq("3.3.0")
        expect(updated.first[:source][:original_string]).to eq("@prettier/plugin-xml@3.3.0")
      end
    end

    it "preserves all requirement properties" do
      updated = checker.updated_requirements("9.0.0")
      expect(updated.first[:groups]).to eq(["additional_dependencies"])
      expect(updated.first[:file]).to eq(".pre-commit-config.yaml")
      expect(updated.first[:source][:type]).to eq("additional_dependency")
      expect(updated.first[:source][:language]).to eq("node")
      expect(updated.first[:source][:hook_id]).to eq("eslint")
      expect(updated.first[:source][:hook_repo]).to eq("https://github.com/pre-commit/mirrors-eslint")
      expect(updated.first[:source][:package_name]).to eq("eslint")
    end
  end
end
