# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nub"
require "dependabot/dependency_graphers"

# TODO: Implement a concrete Nub class
RSpec.describe "Dependabot::DependencyGraphers::Generic" do
  context "with a nub project" do
    subject(:grapher) do
      Dependabot::DependencyGraphers.for_package_manager("nub").new(
        file_parser: parser
      )
    end

    let(:parser) do
      Dependabot::FileParsers.for_package_manager("nub").new(
        dependency_files: project_dependency_files("nub/simple_v1"),
        repo_contents_path: nil,
        source: source,
        credentials: [],
        reject_external_code: false
      )
    end

    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "dependabot-fixtures/nub",
        directory: "/",
        branch: "main"
      )
    end

    it "falls back to the generic grapher" do
      expect(grapher).to be_a(Dependabot::DependencyGraphers::Generic)
    end

    it "specifies the manifest as the relevant dependency file" do
      expect(grapher.relevant_dependency_file.name).to eq("package.json")
    end

    # Nub resolves npm packages, so its package URLs carry npm's type rather than
    # the `generic` fallback the base class uses for unmapped ecosystems.
    it "serializes the resolved dependencies as npm package URLs" do
      expect(grapher.resolved_dependencies.keys).to include(
        "pkg:npm/fetch-factory@0.0.1",
        "pkg:npm/etag@1.8.1"
      )
    end

    it "uses the npm purl type for every resolved dependency" do
      expect(grapher.resolved_dependencies.keys).to all(start_with("pkg:npm/"))
    end
  end
end
