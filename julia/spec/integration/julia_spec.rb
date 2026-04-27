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

    # Integration test for issue #13865: Julia workspaces with different compat specifiers
    # This tests the full pipeline: parser → updater for workspaces where the same dependency
    # has different compat entries in different Project.toml files
    context "with workspace containing different compat specifiers (issue #13865)" do
      let(:fixture_path) { File.join(__dir__, "..", "fixtures", "projects", "workspace_different_compat") }

      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "test/workspace-repo",
          directory: "/"
        )
      end

      let(:main_project_content) { File.read(File.join(fixture_path, "Project.toml")) }
      let(:docs_project_content) { File.read(File.join(fixture_path, "docs", "Project.toml")) }
      let(:test_project_content) { File.read(File.join(fixture_path, "test", "Project.toml")) }
      let(:manifest_content) { File.read(File.join(fixture_path, "Manifest.toml")) }

      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(name: "Project.toml", content: main_project_content, directory: "/"),
          Dependabot::DependencyFile.new(name: "docs/Project.toml", content: docs_project_content, directory: "/"),
          Dependabot::DependencyFile.new(name: "test/Project.toml", content: test_project_content, directory: "/"),
          Dependabot::DependencyFile.new(name: "Manifest.toml", content: manifest_content, directory: "/")
        ]
      end

      it "parses dependencies from all workspace Project.toml files" do
        parser = described_class.file_parser_class.new(
          dependency_files: dependency_files,
          source: source
        )

        dependencies = parser.parse

        # Find the JSON dependency which appears in all 3 Project.toml files
        json_dep = dependencies.find { |d| d.name == "JSON" }
        expect(json_dep).not_to be_nil

        # Should have requirements from all 3 files with their specific compat specifiers
        expect(json_dep.requirements.length).to eq(3)

        main_req = json_dep.requirements.find { |r| r[:file] == "Project.toml" }
        expect(main_req[:requirement]).to eq("0.21.4")

        docs_req = json_dep.requirements.find { |r| r[:file] == "docs/Project.toml" }
        expect(docs_req[:requirement]).to eq("0.21")

        test_req = json_dep.requirements.find { |r| r[:file] == "test/Project.toml" }
        expect(test_req[:requirement]).to eq("0.21")
      end

      it "updates all workspace Project.toml files with their specific requirements" do
        # Create a dependency that represents updating JSON to version 1.0.0
        # Each file should get its previous compat + the new version
        json_dependency = Dependabot::Dependency.new(
          name: "JSON",
          version: "1.0.0",
          previous_version: "0.21.4",
          package_manager: "julia",
          requirements: [
            { requirement: "0.21.4, 1", file: "Project.toml", groups: ["deps"], source: nil },
            { requirement: "0.21, 1", file: "docs/Project.toml", groups: ["deps"], source: nil },
            { requirement: "0.21, 1", file: "test/Project.toml", groups: ["deps"], source: nil }
          ],
          previous_requirements: [
            { requirement: "0.21.4", file: "Project.toml", groups: ["deps"], source: nil },
            { requirement: "0.21", file: "docs/Project.toml", groups: ["deps"], source: nil },
            { requirement: "0.21", file: "test/Project.toml", groups: ["deps"], source: nil }
          ],
          metadata: { julia_uuid: "682c06a0-de6a-54ab-a142-c8b1cf79cde6" }
        )

        updater = described_class.file_updater_class.new(
          dependencies: [json_dependency],
          dependency_files: dependency_files,
          credentials: [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        )

        updated_files = updater.updated_dependency_files

        # Should update all 3 Project.toml files
        project_files = updated_files.select { |f| f.name.end_with?("Project.toml") }
        expect(project_files.length).to eq(3)

        # Verify each file gets its specific updated requirement
        main_project = project_files.find { |f| f.name == "Project.toml" }
        expect(main_project.content).to include('JSON = "0.21.4, 1"')

        docs_project = project_files.find { |f| f.name == "docs/Project.toml" }
        expect(docs_project.content).to include('JSON = "0.21, 1"')

        test_project = project_files.find { |f| f.name == "test/Project.toml" }
        expect(test_project.content).to include('JSON = "0.21, 1"')
      end

      it "handles dependencies unique to specific workspace members" do
        parser = described_class.file_parser_class.new(
          dependency_files: dependency_files,
          source: source
        )

        dependencies = parser.parse

        # Documenter only appears in docs/Project.toml
        documenter_dep = dependencies.find { |d| d.name == "Documenter" }
        expect(documenter_dep).not_to be_nil
        expect(documenter_dep.requirements.length).to eq(1)
        expect(documenter_dep.requirements.first[:file]).to eq("docs/Project.toml")
      end
    end
  end
end
