# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_checkers/ruby"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers::Ruby do
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
      language: "ruby",
      hook_id: "scss-lint",
      hook_repo: "https://github.com/pre-commit/mirrors-scss-lint",
      package_name: "scss_lint",
      original_name: "scss_lint",
      original_string: "scss_lint:0.52.0"
    }
  end

  let(:requirements) do
    [{
      requirement: "0.52.0",
      groups: ["additional_dependencies"],
      file: ".pre-commit-config.yaml",
      source: source
    }]
  end

  let(:current_version) { "0.52.0" }

  describe "#latest_version" do
    # rubocop:disable RSpec/VerifiedDoubleReference
    let(:bundler_checker_class) { class_double("Dependabot::Bundler::UpdateChecker") }
    # rubocop:enable RSpec/VerifiedDoubleReference
    let(:bundler_checker) { instance_double(Dependabot::UpdateCheckers::Base) }
    let(:latest_version_obj) { Gem::Version.new("0.60.0") }

    before do
      allow(Dependabot::UpdateCheckers).to receive(:for_package_manager)
        .with("bundler")
        .and_return(bundler_checker_class)
      allow(bundler_checker_class).to receive(:new).and_return(bundler_checker)
      allow(bundler_checker).to receive(:latest_version).and_return(latest_version_obj)
    end

    it "delegates to bundler UpdateChecker" do
      result = checker.latest_version
      expect(result).to eq("0.60.0")
    end

    it "creates a bundler-compatible dependency" do
      expect(bundler_checker_class).to receive(:new) do |args|
        dep = args[:dependency]
        expect(dep.name).to eq("scss_lint")
        expect(dep.version).to eq("0.52.0")
        expect(dep.package_manager).to eq("bundler")
        bundler_checker
      end

      checker.latest_version
    end

    it "builds a synthetic Gemfile" do
      expect(bundler_checker_class).to receive(:new) do |args|
        files = args[:dependency_files]
        expect(files.length).to eq(1)
        expect(files.first.name).to eq("Gemfile")

        content = files.first.content
        expect(content).to include("source 'https://rubygems.org'")
        expect(content).to include("gem 'scss_lint'")
        bundler_checker
      end

      checker.latest_version
    end

    context "when RubyGems is unreachable" do
      before do
        allow(bundler_checker_class).to receive(:new).and_raise(Dependabot::RegistryError.new(503, "Connection failed"))
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when the gem doesn't exist" do
      before do
        allow(bundler_checker).to receive(:latest_version).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package_name is missing from source" do
      let(:source) { { type: "additional_dependency", language: "ruby" } }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "with a hyphenated gem name" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "ruby",
          hook_id: "rubocop",
          hook_repo: "https://github.com/rubocop/rubocop",
          package_name: "rubocop-rails",
          original_name: "rubocop-rails",
          original_string: "rubocop-rails:2.19.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "2.19.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      let(:current_version) { "2.19.0" }

      it "passes the hyphenated gem name to the bundler checker" do
        expect(bundler_checker_class).to receive(:new) do |args|
          dep = args[:dependency]
          expect(dep.name).to eq("rubocop-rails")
          bundler_checker
        end

        checker.latest_version
      end
    end
  end

  describe "#updated_requirements" do
    context "with exact version (no operator)" do
      let(:requirements) do
        [{
          requirement: "0.52.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "updates to the new exact version" do
        updated = checker.updated_requirements("0.60.0")
        expect(updated.first[:requirement]).to eq("0.60.0")
        expect(updated.first[:source][:original_string]).to eq("scss_lint:0.60.0")
      end
    end

    context "with pessimistic version operator (~>)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "ruby",
          hook_id: "rubocop",
          hook_repo: "https://github.com/rubocop/rubocop",
          package_name: "rubocop",
          original_name: "rubocop",
          original_string: "rubocop:~> 1.50"
        }
      end

      let(:requirements) do
        [{
          requirement: "~> 1.50",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ~> operator" do
        updated = checker.updated_requirements("1.60.0")
        expect(updated.first[:requirement]).to eq("~> 1.60.0")
        expect(updated.first[:source][:original_string]).to eq("rubocop:~> 1.60.0")
      end
    end

    context "with >= operator" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "ruby",
          hook_id: "rubocop",
          hook_repo: "https://github.com/rubocop/rubocop",
          package_name: "rubocop",
          original_name: "rubocop",
          original_string: "rubocop:>= 1.0"
        }
      end

      let(:requirements) do
        [{
          requirement: ">= 1.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the >= operator" do
        updated = checker.updated_requirements("1.60.0")
        expect(updated.first[:requirement]).to eq(">= 1.60.0")
        expect(updated.first[:source][:original_string]).to eq("rubocop:>= 1.60.0")
      end
    end

    context "with = operator" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "ruby",
          hook_id: "rubocop",
          hook_repo: "https://github.com/rubocop/rubocop",
          package_name: "rubocop",
          original_name: "rubocop",
          original_string: "rubocop:= 1.50.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "= 1.50.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the = operator" do
        updated = checker.updated_requirements("1.60.0")
        expect(updated.first[:requirement]).to eq("= 1.60.0")
        expect(updated.first[:source][:original_string]).to eq("rubocop:= 1.60.0")
      end
    end

    it "preserves all requirement properties" do
      updated = checker.updated_requirements("0.60.0")
      expect(updated.first[:groups]).to eq(["additional_dependencies"])
      expect(updated.first[:file]).to eq(".pre-commit-config.yaml")
      expect(updated.first[:source][:type]).to eq("additional_dependency")
      expect(updated.first[:source][:language]).to eq("ruby")
      expect(updated.first[:source][:hook_id]).to eq("scss-lint")
      expect(updated.first[:source][:hook_repo]).to eq("https://github.com/pre-commit/mirrors-scss-lint")
      expect(updated.first[:source][:package_name]).to eq("scss_lint")
    end
  end
end
