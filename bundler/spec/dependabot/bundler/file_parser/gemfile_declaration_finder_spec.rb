# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_parser/gemfile_declaration_finder"

RSpec.describe Dependabot::Bundler::FileParser::GemfileDeclarationFinder do
  let(:checker) do
    described_class.new(gemfile: gemfile)
  end

  let(:dependency) do
    dep = ::Bundler::Dependency.new(dependency_name,
                                    dependency_requirement_sting)
    {
      "name" => dep.name,
      "requirement" => dep.requirement.to_s
    }
  end
  let(:dependency_name) { "business" }
  let(:dependency_requirement_sting) { "~> 1" }

  let(:gemfile) { bundler_project_dependency_file("gemfile", filename: "Gemfile") }

  describe "#gemfile_includes_dependency?" do
    subject(:gemfile_includes_dependency) do
      checker.gemfile_includes_dependency?(dependency)
    end

    context "when the file does not include the dependency" do
      let(:dependency_name) { "dependabot-core" }
      it { is_expected.to eq(false) }
    end

    context "when the file is just comments" do
      let(:gemfile) do
        Dependabot::DependencyFile.new(content: "#Lol this is just a comment", name: "Gemfile")
      end
      it { is_expected.to eq(false) }
    end

    context "when the file does include the dependency" do
      let(:dependency_name) { "business" }
      it { is_expected.to eq(true) }

      context "but it's in a source block" do
        let(:gemfile) { bundler_project_dependency_file("sidekiq_pro", filename: "Gemfile") }
        let(:dependency_name) { "sidekiq-pro" }

        it { is_expected.to eq(true) }
      end

      context "but it's in a group block" do
        let(:gemfile) { bundler_project_dependency_file("development_dependencies", filename: "Gemfile") }
        let(:dependency_name) { "business" }

        it { is_expected.to eq(true) }
      end
    end
  end

  describe "#enhanced_req_string" do
    subject(:enhanced_req_string) { checker.enhanced_req_string(dependency) }

    context "when the file does not include the dependency" do
      let(:dependency_name) { "dependabot-core" }
      it { is_expected.to be_nil }
    end

    context "when the file is just comments" do
      let(:gemfile) do
        Dependabot::DependencyFile.new(content: "#Lol this is just a comment", name: "Gemfile")
      end

      it { is_expected.to be_nil }
    end

    context "when the file does include the dependency" do
      let(:dependency_name) { "business" }
      let(:dependency_requirement_sting) { "~> 1.4.0" }
      it { is_expected.to eq("~> 1.4.0") }

      context "but doesn't specify a requirement" do
        let(:gemfile) { bundler_project_dependency_file("version_not_specified", filename: "Gemfile") }
        let(:dependency_requirement_sting) { nil }

        # NOTE: It would be equally valid to return `nil` here
        it { is_expected.to eq(">= 0") }
      end

      context "but it's in a group block" do
        let(:gemfile_body) do
          fixture("ruby", "gemfiles", "development_dependencies")
        end
        let(:dependency_name) { "business" }
        let(:dependency_requirement_sting) { "~> 1.4.0" }

        it { is_expected.to eq("~> 1.4.0") }
      end

      context "but it's using a version that would be transformed" do
        let(:gemfile) { bundler_project_dependency_file("prerelease_with_dash_gemfile", filename: "Gemfile") }
        let(:dependency_name) { "business" }
        let(:dependency_requirement_sting) { "~> 1.4.0.pre.rc1" }

        it { is_expected.to eq("~> 1.4.0-rc1") }

        context "and doesn't match the original string" do
          let(:dependency_requirement_sting) { "~> 1.4.0.pre.rc2" }
          it { is_expected.to eq("~> 1.4.0.pre.rc2") }
        end
      end

      context "but it's using a function version" do
        let(:gemfile) { bundler_project_dependency_file("function_version_gemfile", filename: "Gemfile") }
        let(:dependency_name) { "business" }
        let(:dependency_requirement_sting) { "~> 1.0.0" }

        it { is_expected.to eq("~> 1.0.0") }
      end
    end
  end
end
