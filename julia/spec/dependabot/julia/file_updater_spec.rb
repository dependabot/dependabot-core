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

  describe "#updated_dependency_files" do
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

    it "updates dependency files" do
      updated_files = updater.updated_dependency_files
      expect(updated_files).not_to be_empty

      # Check that we get both Project.toml and Manifest.toml files back
      project_toml = updated_files.find { |f| f.name == "Project.toml" }
      manifest_toml = updated_files.find { |f| f.name == "Manifest.toml" }

      expect(project_toml).to be_a(Dependabot::DependencyFile)
      expect(manifest_toml).to be_a(Dependabot::DependencyFile)

      # Check that Project.toml has the updated requirement
      expect(project_toml.content).to include('Example = "0.4, 0.5"')

      # Check that Manifest.toml has the updated version
      expect(manifest_toml.content).to include('version = "0.5.5"')
    end

    context "when only Project.toml exists" do
      let(:dependency_files) { [project_file] }

      it "updates only Project.toml" do
        updated_files = updater.updated_dependency_files
        expect(updated_files.length).to eq(1)

        project_toml = updated_files.first
        expect(project_toml.name).to eq("Project.toml")
        expect(project_toml.content).to include('Example = "0.4, 0.5"')
      end
    end

    context "when preserving UUID in [deps] section" do
      let(:project_file_content) do
        <<~TOML
          name = "TestProject"
          uuid = "1234e567-e89b-12d3-a456-789012345678"
          version = "0.1.0"

          [deps]
          Example = "7876af07-990d-54b4-ab0e-23690620f79a"
          StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"

          [compat]
          Example = "0.4"
          StatsBase = "0.34.6"
          julia = "1.10"
        TOML
      end

      let(:project_file) do
        Dependabot::DependencyFile.new(
          name: "Project.toml",
          content: project_file_content
        )
      end

      let(:dependency_files) { [project_file] }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "StatsBase",
          version: "0.35.0",
          previous_version: "0.34.6",
          package_manager: "julia",
          requirements: [{
            requirement: "0.34.6, 0.35",
            file: "Project.toml",
            groups: ["deps"],
            source: nil
          }],
          previous_requirements: [{
            requirement: "0.34.6",
            file: "Project.toml",
            groups: ["deps"],
            source: nil
          }],
          metadata: { julia_uuid: "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91" }
        )
      end

      it "preserves UUID in [deps] section" do
        updated_files = updater.updated_dependency_files
        project_toml = updated_files.first

        # UUID in [deps] section should remain unchanged
        expect(project_toml.content).to include('StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"')
        # But compat entry should be updated
        expect(project_toml.content).to match(/\[compat\].*StatsBase = "0.34.6, 0.35"/m)
        # Make sure UUID wasn't replaced with version in [deps] section
        deps_section = project_toml.content.match(/\[deps\](.*?)\[compat\]/m)[1]
        expect(deps_section).not_to match(/StatsBase\s*=\s*"0\./)
      end

      it "updates only the [compat] section" do
        updated_files = updater.updated_dependency_files
        project_toml = updated_files.first

        # Count occurrences of StatsBase
        deps_match = project_toml.content.match(/\[deps\].*?(StatsBase\s*=\s*"[^"]+").*?\[compat\]/m)
        compat_match = project_toml.content.match(/\[compat\].*?(StatsBase\s*=\s*"[^"]+").*?(?:\z|\[)/m)

        # [deps] should have UUID
        expect(deps_match[1]).to include("2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91")
        # [compat] should have version spec
        expect(compat_match[1]).to include("0.34.6, 0.35")
      end
    end
  end

  private

  def fixture(*path)
    File.read(File.join(__dir__, "..", "..", "fixtures", *path))
  end
end
