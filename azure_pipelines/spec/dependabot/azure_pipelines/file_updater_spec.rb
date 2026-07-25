# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/azure_pipelines/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::AzurePipelines::FileUpdater do
  subject(:updater) do
    described_class.new(
      dependencies: dependencies,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    )]
  end
  let(:dependency_files) { [pipeline_file] }
  let(:pipeline_file) do
    Dependabot::DependencyFile.new(name: "azure-pipelines.yml", content: pipeline_content)
  end
  let(:dependencies) { [dependency] }
  let(:dependency) { build_dependency("Maven", "3", "4") }

  def build_dependency(name, from, to, file: "azure-pipelines.yml")
    Dependabot::Dependency.new(
      name: name,
      version: to,
      previous_version: from,
      package_manager: "azure_pipelines",
      requirements: [{ requirement: to, file: file, source: nil, groups: [] }],
      previous_requirements: [{ requirement: from, file: file, source: nil, groups: [] }]
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    let(:pipeline_content) do
      <<~YAML
        steps:
          # Build the project.
          - task: Maven@3
            inputs:
              mavenPomFile: pom.xml
      YAML
    end

    it "bumps the task and leaves the rest of the file untouched" do
      expect(updater.updated_dependency_files.first.content).to eq(
        <<~YAML
          steps:
            # Build the project.
            - task: Maven@4
              inputs:
                mavenPomFile: pom.xml
        YAML
      )
    end

    context "with a quoted task reference" do
      let(:pipeline_content) { %(steps:\n  - task: "Maven@3"\n  - task: 'Maven@3'\n) }

      it "preserves the quoting style" do
        expect(updater.updated_dependency_files.first.content)
          .to eq(%(steps:\n  - task: "Maven@4"\n  - task: 'Maven@4'\n))
      end
    end

    context "with a trailing comment" do
      let(:pipeline_content) { "steps:\n  - task: Maven@3 # pinned deliberately\n" }

      it "keeps the comment" do
        expect(updater.updated_dependency_files.first.content)
          .to eq("steps:\n  - task: Maven@4 # pinned deliberately\n")
      end
    end

    context "with a task whose name is a prefix of another" do
      let(:dependency) { build_dependency("Docker", "1", "2") }
      let(:pipeline_content) { "steps:\n  - task: Docker@1\n  - task: DockerCompose@1\n" }

      it "only rewrites the task that was updated" do
        expect(updater.updated_dependency_files.first.content)
          .to eq("steps:\n  - task: Docker@2\n  - task: DockerCompose@1\n")
      end
    end

    context "with a full version pin" do
      let(:dependency) { build_dependency("GoTool", "0.3.1", "0.276.0") }
      let(:pipeline_content) { "steps:\n  - task: GoTool@0.3.1\n" }

      it "rewrites the whole version" do
        expect(updater.updated_dependency_files.first.content)
          .to eq("steps:\n  - task: GoTool@0.276.0\n")
      end
    end

    context "when the same task appears more than once" do
      let(:pipeline_content) { "steps:\n  - task: Maven@3\n  - task: Maven@3\n" }

      it "rewrites every occurrence" do
        expect(updater.updated_dependency_files.first.content)
          .to eq("steps:\n  - task: Maven@4\n  - task: Maven@4\n")
      end
    end

    context "when the file spells the task differently to the dependency" do
      # Azure DevOps matches task names case-insensitively, so both spellings are the
      # same dependency, but neither author asked for their casing to be changed.
      let(:pipeline_content) { "steps:\n  - task: maven@3\n  - task: MAVEN@3\n" }

      it "leaves the author's spelling alone" do
        expect(updater.updated_dependency_files.first.content)
          .to eq("steps:\n  - task: maven@4\n  - task: MAVEN@4\n")
      end
    end

    context "when the task is spread across two files" do
      let(:dependency_files) do
        [
          pipeline_file,
          Dependabot::DependencyFile.new(name: "ci/build.yml", content: "steps:\n  - task: Maven@3\n")
        ]
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Maven",
          version: "4",
          previous_version: "3",
          package_manager: "azure_pipelines",
          requirements: [
            { requirement: "4", file: "azure-pipelines.yml", source: nil, groups: [] },
            { requirement: "4", file: "ci/build.yml", source: nil, groups: [] }
          ],
          previous_requirements: [
            { requirement: "3", file: "azure-pipelines.yml", source: nil, groups: [] },
            { requirement: "3", file: "ci/build.yml", source: nil, groups: [] }
          ]
        )
      end

      it "updates both" do
        expect(updater.updated_dependency_files.map(&:name))
          .to contain_exactly("azure-pipelines.yml", "ci/build.yml")
      end
    end

    context "when a file has no requirement for the dependency" do
      let(:dependency_files) do
        [pipeline_file, Dependabot::DependencyFile.new(name: "ci/build.yml", content: "steps:\n  - task: Npm@1\n")]
      end

      it "leaves that file out of the result" do
        expect(updater.updated_dependency_files.map(&:name)).to eq(["azure-pipelines.yml"])
      end
    end

    context "when the reference cannot be found in the file it was parsed from" do
      let(:pipeline_content) { "steps:\n  - script: echo nothing to see here\n" }

      it "raises rather than silently producing an unchanged file" do
        expect { updater.updated_dependency_files }
          .to raise_error(Dependabot::DependencyFileContentNotChanged)
      end
    end
  end

  describe ".updated_files_regex" do
    it "matches YAML files" do
      expect(described_class.updated_files_regex.any? { |re| "azure-pipelines.yml".match?(re) }).to be(true)
      expect(described_class.updated_files_regex.any? { |re| "ci/build.yaml".match?(re) }).to be(true)
    end
  end
end
