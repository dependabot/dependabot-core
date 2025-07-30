# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/pdm_file_updater"

RSpec.describe Dependabot::Python::FileUpdater::PdmFileUpdater do
  let(:updater) do
    described_class.new(
      dependencies: dependencies,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:dependencies) { [dependency] }
  let(:dependency_files) { [pyproject, lockfile] }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: pyproject_content
    )
  end
  let(:pyproject_content) { fixture("projects/pdm", "pyproject.toml") }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "pdm.lock",
      content: fixture("projects/pdm", "pdm.lock")
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "requests" }
  let(:dependency_version) { "2.28.0" }
  let(:previous_version) { "2.25.0" }
  let(:groups) { [] }
  let(:requirements) do
    [{
      file: "pyproject.toml",
      requirement: "~=2.28",
      groups: groups,
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "pyproject.toml",
      requirement: "~=2.25",
      groups: groups,
      source: nil
    }]
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    context "with a dependency defined under PEP 621 project dependencies" do
      it "updates the pyproject.toml and lockfile" do
        expect(updated_files.count).to eq(2)

        pyproject_file = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(pyproject_file.content).to include("requests~=2.28")
        expect(pyproject_file.content).not_to include("requests~=2.25")

        lockfile = updated_files.find { |f| f.name == "pdm.lock" }
        expect(lockfile).not_to be_nil
        # The lockfile content will be updated by PDM
        expect(lockfile.content).to be_a(String)
      end
    end

    context "with a dependency defined under tool.pdm" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "demo"
          version = "0.1.0"

          [tool.pdm.dev-dependencies]
          lint = [
              "requests~=2.25",
          ]
        TOML
      end

      let(:groups) { ["lint"] }

      it "updates the pyproject.toml and lockfile" do
        expect(updated_files.count).to eq(2)

        pyproject_file = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(pyproject_file.content).to include("requests~=2.28")
        expect(pyproject_file.content).not_to include("requests~=2.25")

        original_hash = TomlRB.parse(lockfile.content)["metadata"]["content_hash"]
        new_lockfile = updated_files.find { |f| f.name == "pdm.lock" }
        new_hash = TomlRB.parse(new_lockfile.content)["metadata"]["content_hash"]
        expect(new_hash).not_to eq(original_hash)
      end
    end

    context "with a dependency defined under dependency groups" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "demo"
          version = "0.1.0"

          [dependency-groups]
          lint = [
              "requests~=2.25",
          ]
        TOML
      end

      let(:groups) { ["lint"] }

      it "updates the pyproject.toml and lockfile" do
        expect(updated_files.count).to eq(2)

        pyproject_file = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(pyproject_file.content).to include("requests~=2.28")
        expect(pyproject_file.content).not_to include("requests~=2.25")
      end
    end

    context "when only lockfile needs updating" do
      let(:requirements) { previous_requirements }

      it "only updates the lockfile" do
        expect(updated_files.count).to eq(1)

        lockfile = updated_files.find { |f| f.name == "pdm.lock" }
        expect(lockfile).not_to be_nil
      end
    end

    context "with subdependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "idna",
          version: "3.5",
          previous_version: "3.4",
          requirements: [],
          previous_requirements: [],
          package_manager: "pip",
          subdependency_metadata: [
            {
              production: true,
              groups: ["default"],
              req: "idna==3.5"
            }
          ]
        )
      end

      it "only updates the lockfile" do
        expect(updated_files.count).to eq(1)

        lockfile = updated_files.find { |f| f.name == "pdm.lock" }
        expect(lockfile).not_to be_nil

        data = TomlRB.parse(lockfile.content)

        idna_data = data["package"].find { |d| d["name"] == "idna" }
        expect(idna_data["version"]).to eq("3.5")
      end
    end

    context "with optional dependencies" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "demo"
          version = "0.1.0"
          dependencies = []

          [project.optional-dependencies]
          lint = [
              "requests~=2.25",
          ]
        TOML
      end
      let(:requirements) do
        [{
          file: "pyproject.toml",
          requirement: "~=2.28",
          groups: ["lint"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "pyproject.toml",
          requirement: "~=2.25",
          groups: ["lint"],
          source: nil
        }]
      end

      it "updates optional dependencies" do
        pyproject_file = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(pyproject_file.content).to include("requests~=2.28")
        expect(pyproject_file.content).not_to include("requests~=2.25")
      end
    end
  end
end
