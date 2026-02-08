# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_parsers/python"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyParsers::Python do
  let(:parser) do
    described_class.new(
      dep_string: dep_string,
      hook_id: "mypy",
      repo_url: "https://github.com/pre-commit/mirrors-mypy",
      file_name: ".pre-commit-config.yaml"
    )
  end

  describe "#parse" do
    context "with exact version constraint (==)" do
      let(:dep_string) { "types-requests==2.31.0.1" }

      it "parses the dependency correctly" do
        dependency = parser.parse
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("https://github.com/pre-commit/mirrors-mypy::mypy::types-requests")
        expect(dependency.version).to eq("2.31.0.1")
        expect(dependency.package_manager).to eq("pre_commit")

        requirement = dependency.requirements.first
        expect(requirement[:requirement]).to eq("==2.31.0.1")
        expect(requirement[:groups]).to eq(["additional_dependencies"])
        expect(requirement[:file]).to eq(".pre-commit-config.yaml")
        expect(requirement[:source][:type]).to eq("additional_dependency")
        expect(requirement[:source][:language]).to eq("python")
        expect(requirement[:source][:hook_id]).to eq("mypy")
        expect(requirement[:source][:repo_url]).to eq("https://github.com/pre-commit/mirrors-mypy")
        expect(requirement[:source][:package_name]).to eq("types-requests")
        expect(requirement[:source][:original_name]).to eq("types-requests")
        expect(requirement[:source][:original_string]).to eq("types-requests==2.31.0.1")
      end
    end

    context "with minimum version constraint (>=)" do
      let(:dep_string) { "flake8>=5.0.0" }

      it "parses the dependency with >= operator" do
        dependency = parser.parse
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("https://github.com/pre-commit/mirrors-mypy::mypy::flake8")
        expect(dependency.version).to eq("5.0.0")

        requirement = dependency.requirements.first
        expect(requirement[:requirement]).to eq(">=5.0.0")
        expect(requirement[:source][:package_name]).to eq("flake8")
        expect(requirement[:source][:original_string]).to eq("flake8>=5.0.0")
      end
    end

    context "with compatible release constraint (~=)" do
      let(:dep_string) { "pytest~=7.0" }

      it "parses the dependency with ~= operator" do
        dependency = parser.parse
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("https://github.com/pre-commit/mirrors-mypy::mypy::pytest")
        expect(dependency.version).to eq("7.0")

        requirement = dependency.requirements.first
        expect(requirement[:requirement]).to eq("~=7.0")
        expect(requirement[:source][:package_name]).to eq("pytest")
        expect(requirement[:source][:original_string]).to eq("pytest~=7.0")
      end
    end

    context "with extras in package name" do
      let(:dep_string) { "black[d]>=23.0.0" }

      it "parses the dependency and extracts package name without extras" do
        dependency = parser.parse
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("https://github.com/pre-commit/mirrors-mypy::mypy::black")
        expect(dependency.version).to eq("23.0.0")

        requirement = dependency.requirements.first
        expect(requirement[:requirement]).to eq(">=23.0.0")
        expect(requirement[:source][:package_name]).to eq("black")
        expect(requirement[:source][:original_name]).to eq("black[d]")
        expect(requirement[:source][:original_string]).to eq("black[d]>=23.0.0")
      end
    end

    context "with multiple extras" do
      let(:dep_string) { "httpx[http2,cli]>=0.24.0" }

      it "extracts package name correctly" do
        dependency = parser.parse
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("https://github.com/pre-commit/mirrors-mypy::mypy::httpx")
        expect(dependency.version).to eq("0.24.0")

        requirement = dependency.requirements.first
        expect(requirement[:source][:package_name]).to eq("httpx")
        expect(requirement[:source][:original_name]).to eq("httpx[http2,cli]")
        expect(requirement[:source][:original_string]).to eq("httpx[http2,cli]>=0.24.0")
      end
    end

    context "with other version constraint operators" do
      {
        "package<=1.0.0" => "<=",
        "package>1.0.0" => ">",
        "package<2.0.0" => "<",
        "package!=1.5.0" => "!=",
        "package===1.0.0" => "==="
      }.each do |dep_str, operator|
        context "with #{operator} operator" do
          let(:dep_string) { dep_str }

          it "parses correctly" do
            dependency = parser.parse
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.requirements.first[:requirement]).to start_with(operator)
          end
        end
      end
    end

    context "with package names containing hyphens and underscores" do
      let(:dep_string) { "typing-extensions>=4.0.0" }

      it "parses package names with special characters" do
        dependency = parser.parse
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("https://github.com/pre-commit/mirrors-mypy::mypy::typing-extensions")

        requirement = dependency.requirements.first
        expect(requirement[:source][:package_name]).to eq("typing-extensions")
      end
    end

    context "with invalid dependency string" do
      let(:dep_string) { "invalid-no-version" }

      it "returns nil" do
        expect(parser.parse).to be_nil
      end
    end

    context "with empty string" do
      let(:dep_string) { "" }

      it "returns nil" do
        expect(parser.parse).to be_nil
      end
    end
  end

  describe ".parse (class method)" do
    let(:dep_string) { "types-requests==2.31.0.1" }

    it "provides a convenient class method interface" do
      dependency = described_class.parse(
        dep_string: dep_string,
        hook_id: "mypy",
        repo_url: "https://github.com/pre-commit/mirrors-mypy",
        file_name: ".pre-commit-config.yaml"
      )

      expect(dependency).to be_a(Dependabot::Dependency)
      expect(dependency.name).to eq("https://github.com/pre-commit/mirrors-mypy::mypy::types-requests")
      expect(dependency.version).to eq("2.31.0.1")
    end
  end

  describe "dependency name uniqueness" do
    it "creates unique names for same package in different hooks" do
      dep1 = described_class.parse(
        dep_string: "flake8>=5.0.0",
        hook_id: "mypy",
        repo_url: "https://github.com/pre-commit/mirrors-mypy",
        file_name: ".pre-commit-config.yaml"
      )

      dep2 = described_class.parse(
        dep_string: "flake8>=5.0.0",
        hook_id: "black",
        repo_url: "https://github.com/psf/black",
        file_name: ".pre-commit-config.yaml"
      )

      expect(dep1.name).not_to eq(dep2.name)
      expect(dep1.name).to include("mypy")
      expect(dep2.name).to include("black")
    end
  end
end
