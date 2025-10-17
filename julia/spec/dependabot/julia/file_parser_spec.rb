# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/julia/file_parser"

RSpec.describe Dependabot::Julia::FileParser do
  describe "#parse with actual fixtures" do
    subject(:dependencies) { parser.parse }

    let(:parser) do
      described_class.new(
        dependency_files: dependency_files,
        source: source,
        credentials: credentials
      )
    end

    let(:dependency_files) { [project_file, manifest_file] }
    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "test/test",
        directory: "/"
      )
    end
    let(:credentials) { [] }

    let(:project_file) do
      Dependabot::DependencyFile.new(
        name: "Project.toml",
        content: fixture("projects", "basic", "Project.toml")
      )
    end

    let(:manifest_file) do
      Dependabot::DependencyFile.new(
        name: "Manifest.toml",
        content: fixture("projects", "basic", "Manifest.toml")
      )
    end

    it "parses dependencies correctly" do
      expect(dependencies.length).to eq(1)

      example_dep = dependencies.find { |d| d.name == "Example" }
      expect(example_dep).to be_a(Dependabot::Dependency)
      expect(example_dep.name).to eq("Example")
      expect(example_dep.version).to eq("0.4.1")
      expect(example_dep.package_manager).to eq("julia")

      requirement = example_dep.requirements.first
      expect(requirement[:requirement]).to eq("0.4")
      expect(requirement[:file]).to eq("Project.toml")
      expect(requirement[:groups]).to eq(["runtime"])
    end

    context "when only Project.toml exists (no Manifest.toml)" do
      let(:dependency_files) { [project_file] }

      it "parses dependencies without exact versions" do
        expect(dependencies.length).to eq(1)

        example_dep = dependencies.find { |d| d.name == "Example" }
        expect(example_dep.name).to eq("Example")
        expect(example_dep.version).to be_nil # No Manifest.toml to get exact version
        expect(example_dep.requirements.first[:requirement]).to eq("0.4")
      end
    end
  end

  private

  def fixture(type, *names)
    File.read(File.join("spec", "fixtures", type, *names))
  end
end
