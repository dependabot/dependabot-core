# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"

require "dependabot/azure_pipelines/file_parser"
require "dependabot/azure_pipelines/requirement"

require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::AzurePipelines::FileParser do
  let(:dependencies) { parser.parse }
  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
  let(:files) do
    project_dependency_files(project_name, directory: directory)
  end
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/dotnet-sdk-example",
      directory: directory
    )
  end
  let(:parser) do
    described_class.new(dependency_files: files, source: source, repo_contents_path: repo_contents_path)
  end

  it_behaves_like "a dependency file parser"

  shared_examples_for "parse" do
    it "parses dependencies fine" do
      expect(dependencies.size).to eq(expectations.size)

      expectations.each do |expected|
        version = expected[:version]
        name = expected[:name]
        requirements = expected[:requirements]
        metadata = expected[:metadata]

        dependency = dependencies.find { |dep| dep.name == name }
        expect(dependency).to have_attributes(
          name: name,
          version: version,
          requirements: requirements,
          metadata: metadata
        )
      end

      ecosystem = parser.ecosystem

      expect(ecosystem.name).to eq("azure-pipelines")
      expect(ecosystem.package_manager.name).to eq("azure_pipelines")
    end
  end

  context "with an azure-pipelines.yml with steps" do
    let(:project_name) { "file_in_root" }

    let(:expectations) do
      [
        {
          name: "NodeTool",
          version: "0",
          requirements: [{
            file: "/azure-pipelines.yml",
            groups: [],
            requirement: "0",
            source: nil
          }],
          metadata: {}
        }
      ].freeze
    end

    it_behaves_like "parse"
  end

  context "with an azure-pipelines.yml with jobs" do
    let(:project_name) { "jobs" }

    let(:expectations) do
      [
        { name: "Maven", version: "4" },
        { name: "Gradle", version: "3" }
      ].map do |entry|
        {
          name: entry[:name],
          version: entry[:version],
          requirements: [{
            file: "/azure-pipelines.yaml",
            groups: [],
            requirement: entry[:version],
            source: nil
          }],
          metadata: {}
        }
      end.freeze
    end

    it_behaves_like "parse"
  end

  context "with an azure-pipelines.yml with stages" do
    let(:project_name) { "stages" }

    let(:expectations) do
      [
        { name: "Maven", version: "4" },
        { name: "Gradle", version: "3" },
        { name: "DockerCompose", version: "1" },
        { name: "Docker", version: "1" }
      ].map do |entry|
        {
          name: entry[:name],
          version: entry[:version],
          requirements: [{
            file: "/azure-pipelines.yaml",
            groups: [],
            requirement: entry[:version],
            source: nil
          }],
          metadata: {}
        }
      end.freeze
    end

    it_behaves_like "parse"
  end
end
