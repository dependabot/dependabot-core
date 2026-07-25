# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/azure_pipelines/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::AzurePipelines::FileParser do
  subject(:parser) { described_class.new(dependency_files: files, source: source) }

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/")
  end
  let(:files) { [pipeline_file] }
  let(:pipeline_file) do
    Dependabot::DependencyFile.new(name: "azure-pipelines.yml", content: pipeline_content)
  end
  let(:pipeline_content) { fixture("projects", "simple", "azure-pipelines.yml") }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    context "with tasks under a root steps block" do
      it "returns a dependency per task" do
        expect(parser.parse.map(&:name)).to contain_exactly("UseDotNet", "PublishTestResults")
      end

      it "records the pinned version and requirement" do
        dependency = parser.parse.find { |dep| dep.name == "UseDotNet" }

        expect(dependency.version).to eq("2")
        expect(dependency.requirements).to eq(
          [{ requirement: "2", file: "azure-pipelines.yml", source: nil, groups: [] }]
        )
      end
    end

    context "with tasks nested in stages, jobs and deployment strategies" do
      let(:pipeline_content) { fixture("projects", "stages", "azure-pipelines.yml") }

      it "finds tasks at every level of nesting" do
        expect(parser.parse.map(&:name))
          .to contain_exactly("Maven", "Gradle", "Docker", "AzureWebApp", "PublishBuildArtifacts")
      end
    end

    context "with references that cannot be resolved statically" do
      let(:pipeline_content) { fixture("projects", "edge_cases", "azure-pipelines.yml") }

      it "keeps the references it can resolve, including quoted ones" do
        expect(parser.parse.map(&:name))
          .to include("CmdLine", "GoTool", "Npm", "CopyFiles", "31c75bbb-bcdf-4706-8d7c-4da6a1959bc2")
      end

      it "preserves the precision of a fully pinned version" do
        expect(parser.parse.find { |dep| dep.name == "GoTool" }.version).to eq("0.3.1")
      end

      it "skips names and versions built from template expressions" do
        names = parser.parse.map(&:name)

        expect(names).not_to include("Bash")
        expect(names.none? { |name| name.include?("$") }).to be(true)
      end

      # `Fake` appears three times in the fixture: as a variable named `task`, as a
      # task input named `task`, and inside a script string. A step is always a list
      # entry, so none of them is one.
      it "only treats list entries as steps" do
        expect(parser.parse.map(&:name)).not_to include("Fake")
      end
    end

    context "with the same task pinned in two files" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(name: "azure-pipelines.yml", content: "steps:\n  - task: Maven@3\n"),
          Dependabot::DependencyFile.new(name: "ci/build.yml", content: "steps:\n  - task: Maven@3\n")
        ]
      end

      it "returns a single dependency carrying both requirements" do
        dependencies = parser.parse

        expect(dependencies.length).to eq(1)
        expect(dependencies.first.requirements.map { |req| req[:file] })
          .to contain_exactly("azure-pipelines.yml", "ci/build.yml")
      end
    end

    context "with a file that is not a pipeline" do
      let(:pipeline_content) { fixture("projects", "not_a_pipeline", "config.yml") }

      it "returns no dependencies rather than raising" do
        expect(parser.parse).to be_empty
      end
    end

    context "with an empty file" do
      let(:pipeline_content) { "" }

      it "returns no dependencies" do
        expect(parser.parse).to be_empty
      end
    end

    context "with invalid YAML" do
      let(:pipeline_content) { "steps:\n  - task: Maven@3\n   bad indent: [" }

      it "raises DependencyFileNotParseable" do
        expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end

  describe "#ecosystem" do
    it "reports the package manager" do
      expect(parser.ecosystem.name).to eq("azure-pipelines")
      expect(parser.ecosystem.package_manager.name).to eq("azure_pipelines")
    end
  end
end
