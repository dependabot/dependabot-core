# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/update_checker"
require "dependabot/pre_commit/additional_dependency_checkers/dart"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers::Dart do
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
      language: "dart",
      hook_id: "dart-format",
      hook_repo: "https://github.com/aspect-build/rules_lint",
      package_name: "intl",
      original_name: "intl",
      original_string: "intl:0.18.0"
    }
  end

  let(:requirements) do
    [{
      requirement: "0.18.0",
      groups: ["additional_dependencies"],
      file: ".pre-commit-config.yaml",
      source: source
    }]
  end

  let(:current_version) { "0.18.0" }

  describe "#latest_version" do
    let(:pub_checker_class) { class_double(Dependabot::Pub::UpdateChecker) }
    let(:pub_checker) { instance_double(Dependabot::UpdateCheckers::Base) }
    let(:latest_version_obj) { Gem::Version.new("0.19.0") }

    before do
      allow(Dependabot::UpdateCheckers).to receive(:for_package_manager)
        .with("pub")
        .and_return(pub_checker_class)
      allow(pub_checker_class).to receive(:new).and_return(pub_checker)
      allow(pub_checker).to receive(:latest_version).and_return(latest_version_obj)
    end

    it "delegates to pub UpdateChecker" do
      result = checker.latest_version
      expect(result).to eq("0.19.0")
    end

    it "creates a pub-compatible dependency" do
      expect(pub_checker_class).to receive(:new) do |args|
        dep = args[:dependency]
        expect(dep.name).to eq("intl")
        expect(dep.version).to eq("0.18.0")
        expect(dep.package_manager).to eq("pub")
        pub_checker
      end

      checker.latest_version
    end

    it "builds a synthetic pubspec.yaml" do
      expect(pub_checker_class).to receive(:new) do |args|
        files = args[:dependency_files]
        expect(files.length).to eq(1)
        expect(files.first.name).to eq("pubspec.yaml")
        expect(files.first.content).to include("intl: ^0.18.0")
        pub_checker
      end

      checker.latest_version
    end

    context "when the pub.dev registry is unreachable" do
      before do
        allow(pub_checker_class).to receive(:new).and_raise(Dependabot::RegistryError.new(503, "Connection failed"))
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when the package doesn't exist" do
      before do
        allow(pub_checker).to receive(:latest_version).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package_name is missing from source" do
      let(:source) { { type: "additional_dependency", language: "dart" } }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    context "with exact version (no operator)" do
      it "updates to the new exact version" do
        updated = checker.updated_requirements("0.19.0")
        expect(updated.first[:requirement]).to eq("0.19.0")
        expect(updated.first[:source][:original_string]).to eq("intl:0.19.0")
      end
    end

    context "with caret range (^)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "dart",
          hook_id: "dart-analyze",
          hook_repo: "https://github.com/nickmeinhold/pre-commit-dart",
          package_name: "json_annotation",
          original_name: "json_annotation",
          original_string: "json_annotation:^4.8.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "^4.8.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ^ operator" do
        updated = checker.updated_requirements("4.9.0")
        expect(updated.first[:requirement]).to eq("^4.9.0")
        expect(updated.first[:source][:original_string]).to eq("json_annotation:^4.9.0")
      end
    end

    context "with tilde range (~)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "dart",
          hook_id: "custom-dart-hook",
          hook_repo: "https://github.com/example/dart-hooks",
          package_name: "yaml",
          original_name: "yaml",
          original_string: "yaml:~3.1.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "~3.1.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ~ operator" do
        updated = checker.updated_requirements("3.2.0")
        expect(updated.first[:requirement]).to eq("~3.2.0")
        expect(updated.first[:source][:original_string]).to eq("yaml:~3.2.0")
      end
    end

    context "with >= constraint" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "dart",
          hook_id: "dart-analyze",
          hook_repo: "https://github.com/nickmeinhold/pre-commit-dart",
          package_name: "collection",
          original_name: "collection",
          original_string: "collection:>=1.17.0"
        }
      end

      let(:requirements) do
        [{
          requirement: ">=1.17.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the >= operator" do
        updated = checker.updated_requirements("1.18.0")
        expect(updated.first[:requirement]).to eq(">=1.18.0")
        expect(updated.first[:source][:original_string]).to eq("collection:>=1.18.0")
      end
    end

    it "preserves all requirement properties" do
      updated = checker.updated_requirements("0.19.0")
      expect(updated.first[:groups]).to eq(["additional_dependencies"])
      expect(updated.first[:file]).to eq(".pre-commit-config.yaml")
      expect(updated.first[:source][:type]).to eq("additional_dependency")
      expect(updated.first[:source][:language]).to eq("dart")
      expect(updated.first[:source][:hook_id]).to eq("dart-format")
      expect(updated.first[:source][:hook_repo]).to eq("https://github.com/aspect-build/rules_lint")
      expect(updated.first[:source][:package_name]).to eq("intl")
    end
  end
end
