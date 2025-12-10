# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia"

RSpec.describe Dependabot::Julia::FileUpdater do
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

  describe "FileUpdater integration test" do
    subject(:updater) do
      described_class.new(
        dependencies: [dependency],
        dependency_files: dependency_files,
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }]
      )
    end

    describe "#updated_dependency_files" do
      let(:dependency_files) { [project_file, manifest_file] }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Example",
          version: "0.5.5",
          previous_version: "0.4.1",
          package_manager: "julia",
          requirements: [{
            requirement: "0.4, 0.5",
            file: "Project.toml",
            groups: ["deps"],
            source: nil
          }],
          previous_requirements: [{
            requirement: "0.4",
            file: "Project.toml",
            groups: ["deps"],
            source: nil
          }],
          metadata: { julia_uuid: "7876af07-990d-54b4-ab0e-23690620f79a" }
        )
      end

      it "successfully updates files in integration context" do
        updated_files = updater.updated_dependency_files
        expect(updated_files).not_to be_empty

        # Check that both files are updated
        expect(updated_files.length).to eq(2)

        project_toml = updated_files.find { |f| f.name == "Project.toml" }
        manifest_toml = updated_files.find { |f| f.name == "Manifest.toml" }

        expect(project_toml).to be_a(Dependabot::DependencyFile)
        expect(manifest_toml).to be_a(Dependabot::DependencyFile)

        expect(project_toml.content).to include('Example = "0.4, 0.5"')
        expect(manifest_toml.content).to include('version = "0.5.5"')
      end
    end
  end

  private

  def fixture(*path)
    File.read(File.join(__dir__, "..", "..", "fixtures", *path))
  end
end
