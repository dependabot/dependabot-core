# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia"

RSpec.describe Dependabot::Julia do
  describe "integration" do
    it "handles basic dependency updates" do
      dependency = Dependabot::Dependency.new(
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

      # Use actual fixture files for proper testing
      project_content = File.read(File.join(__dir__, "..", "fixtures", "projects", "basic", "Project.toml"))
      manifest_content = File.read(File.join(__dir__, "..", "fixtures", "projects", "basic", "Manifest.toml"))

      dependency_files = [
        Dependabot::DependencyFile.new(name: "Project.toml", content: project_content),
        Dependabot::DependencyFile.new(name: "Manifest.toml", content: manifest_content)
      ]

      updater = described_class.file_updater_class.new(
        dependencies: [dependency],
        dependency_files: dependency_files,
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }]
      )

      updated_files = updater.updated_dependency_files

      # Expect files to be updated
      expect(updated_files).not_to be_empty

      project_toml = updated_files.find { |f| f.name == "Project.toml" }
      manifest_toml = updated_files.find { |f| f.name == "Manifest.toml" }

      expect(project_toml).to be_a(Dependabot::DependencyFile)
      expect(project_toml.content).to include('Example = "0.4, 0.5"')

      expect(manifest_toml).to be_a(Dependabot::DependencyFile)
      expect(manifest_toml.content).to include('version = "0.5.5"')
    end
  end
end
