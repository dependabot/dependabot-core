require "spec_helper"
require "dependabot/julia"

RSpec.describe "Julia integration" do
  subject(:updater) do
    Dependabot::FileUpdaters::Integrated::Julia.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  describe "package version update" do
    let(:dependency_files) { project_dependency_files("basic") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "Example",
        version: "0.5.0",
        previous_version: "0.4.0",
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
        }]
      )
    end

    it "updates the manifest successfully" do
      updated_files = updater.updated_dependency_files
      expect(updated_files).not_to be_empty

      project_toml = updated_files.find { |f| f.name == "Project.toml" }
      manifest_toml = updated_files.find { |f| f.name == "Manifest.toml" }

      # Verify Project.toml changes
      expect(project_toml).to be_a(Dependabot::DependencyFile)
      expect(project_toml.content).to include('Example = "0.5.0"')

      # Verify Manifest.toml changes  
      expect(manifest_toml).to be_a(Dependabot::DependencyFile)
      expect(manifest_toml.content).to include('"Example"')
      expect(manifest_toml.content).to include('"version" = "0.5.0"')
    end

    context "with private registries" do
      # Add tests for private registry authentication
    end
  end
end
