# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_parser/gemspec_declaration_finder"

RSpec.describe Dependabot::Bundler::FileParser::GemspecDeclarationFinder do
  let(:checker) do
    described_class.new(gemspec: gemspec)
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

  let(:gemspec) { bundler_project_dependency_file("gemspec_loads_another", filename: "example.gemspec") }

  describe "#gemspec_includes_dependency?" do
    subject(:gemspec_includes_dependency) do
      checker.gemspec_includes_dependency?(dependency)
    end

    context "when the file does not include the dependency" do
      let(:dependency_name) { "dependabot-core" }
      it { is_expected.to eq(false) }
    end

    context "when the file does include the dependency as `add_dependency`" do
      let(:dependency_name) { "excon" }
      it { is_expected.to eq(true) }
    end

    context "when the file does include the dependency as `add_runtime_dependency`" do
      let(:dependency_name) { "bundler" }
      it { is_expected.to eq(true) }
    end

    context "when the file does include the dependency as `add_development_dependency`" do
      let(:dependency_name) { "webmock" }
      it { is_expected.to eq(true) }
    end

    context "when the file loads the dependency dynamically" do
      let(:dependency_name) { "rake" }
      it { is_expected.to eq(false) }
    end
  end
end
