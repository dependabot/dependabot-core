# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia"

RSpec.describe Dependabot::Julia::FileUpdater do
  describe ".file_updater_class" do
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
      let(:dependency_files) { project_dependency_files("basic") }
      let(:dependency) do
        Dependabot::Julia::Dependency.new(
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
        expect(project_toml.content).to include('Example = "0.4, 0.5"')

        # Verify Manifest.toml changes
        expect(manifest_toml).to be_a(Dependabot::DependencyFile)
        expect(manifest_toml.content).to include('[[deps.Example]]\ngit-tree-sha1 = "e1f0e1a832ccd8e97d6d0348dec33ee139a5aeaf"\nuuid = "7876af07-990d-54b4-ab0e-23690620f79a"\nversion = "0.5.5"')
      end
    end
  end
end
