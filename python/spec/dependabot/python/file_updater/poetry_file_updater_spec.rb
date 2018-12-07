# frozen_string_literal: true

require "toml-rb"

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/poetry_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Python::FileUpdater::PoetryFileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:dependency_files) { [pyproject, lockfile] }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("python", "pyproject_files", pyproject_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "pyproject.lock",
      content: fixture("python", "pyproject_locks", lockfile_fixture_name)
    )
  end
  let(:pyproject_fixture_name) { "version_not_specified.toml" }
  let(:lockfile_fixture_name) { "version_not_specified.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.19.1",
      previous_version: "2.18.0",
      package_manager: "pip",
      requirements: [{
        requirement: "*",
        file: "pyproject.toml",
        source: nil,
        groups: ["dependencies"]
      }],
      previous_requirements: [{
        requirement: "*",
        file: "pyproject.toml",
        source: nil,
        groups: ["dependencies"]
      }]
    )
  end
  let(:dependency_name) { "requests" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "updates the lockfile successfully (and doesn't affect other deps)" do
      expect(updated_files.map(&:name)).to eq(%w(pyproject.lock))

      updated_lockfile = updated_files.find { |f| f.name == "pyproject.lock" }

      lockfile_obj = TomlRB.parse(updated_lockfile.content)
      requests = lockfile_obj["package"].find { |d| d["name"] == "requests" }
      pytest = lockfile_obj["package"].find { |d| d["name"] == "pytest" }

      expect(requests["version"]).to eq("2.19.1")
      expect(pytest["version"]).to eq("3.5.0")

      expect(lockfile_obj["metadata"]["content-hash"]).
        to start_with("82505f37a0da79b1e0f8d5c715d5435ef9318adf4df0e7372bde")
    end

    context "with a specified Python version" do
      let(:pyproject_fixture_name) { "python_2.toml" }
      let(:lockfile_fixture_name) { "python_2.lock" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "2.19.1",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "2.19.1",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "2.18.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      it "updates the lockfile successfully" do
        updated_lockfile = updated_files.find { |f| f.name == "pyproject.lock" }

        lockfile_obj = TomlRB.parse(updated_lockfile.content)
        requests = lockfile_obj["package"].find { |d| d["name"] == "requests" }
        expect(requests["version"]).to eq("2.19.1")
      end
    end

    context "without a lockfile" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "caret_version.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "2.19.1",
          previous_version: nil,
          package_manager: "pip",
          requirements: [{
            requirement: "^2.19.1",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "^1.0.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      it "updates the pyproject.toml" do
        expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

        updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_lockfile.content).to include('requests = "^2.19.1"')
      end
    end

    context "with a poetry.lock" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: fixture("python", "pyproject_locks", lockfile_fixture_name)
        )
      end

      it "updates the lockfile successfully" do
        expect(updated_files.map(&:name)).to eq(%w(poetry.lock))

        updated_lockfile = updated_files.find { |f| f.name == "poetry.lock" }

        lockfile_obj = TomlRB.parse(updated_lockfile.content)
        requests = lockfile_obj["package"].find { |d| d["name"] == "requests" }
        pytest = lockfile_obj["package"].find { |d| d["name"] == "pytest" }

        expect(requests["version"]).to eq("2.19.1")
        expect(pytest["version"]).to eq("3.5.0")

        expect(lockfile_obj["metadata"]["content-hash"]).
          to start_with("82505f37a0da79b1e0f8d5c715d5435ef9318adf4df0e7372bde")
      end
    end
  end
end
