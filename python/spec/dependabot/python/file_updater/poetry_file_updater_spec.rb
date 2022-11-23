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
      content: fixture("pyproject_files", pyproject_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "pyproject.lock",
      content: fixture("pyproject_locks", lockfile_fixture_name)
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
        to start_with("8cea4ecb5b2230fbd4a33a67a4da004f1ccabad48352aaf040")
    end

    context "with a specified Python version" do
      let(:pyproject_fixture_name) { "python_310.toml" }
      let(:lockfile_fixture_name) { "python_310.lock" }

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
      it "does not change python version" do
        updated_pyproj = updated_files.find { |f| f.name == "pyproject.toml" }
        pyproj_obj = TomlRB.parse(updated_pyproj.content)
        pyproj_obj["tool"]["poetry"]["dependencies"]["python"] == "3.10.7"
      end
    end

    context "with a supported python version", :slow do
      let(:python_version) { "3.6.9" }
      let(:pyproject_fixture_name) { "python_36.toml" }
      let(:lockfile_fixture_name) { "python_36.lock" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "django",
          version: "3.1",
          previous_version: "3.0",
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
      it "updates the lockfile" do
        updated_lockfile = updated_files.find { |f| f.name == "pyproject.lock" }

        lockfile_obj = TomlRB.parse(updated_lockfile.content)
        requests = lockfile_obj["package"].find { |d| d["name"] == "django" }
        expect(requests["version"]).to eq("3.1")
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

    context "without a lockfile and with an indented pyproject.toml" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "indented.toml" }
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
        expect(updated_lockfile.content).to include('  requests = "^2.19.1"')
      end
    end

    context "with a poetry.lock" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: fixture("pyproject_locks", lockfile_fixture_name)
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
          to start_with("8cea4ecb5b2230fbd4a33a67a4da004f1ccabad48352aaf040a1d")
      end

      context "with a sub-dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "2018.11.29",
            previous_version: "2018.4.16",
            package_manager: "pip",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependency_name) { "certifi" }

        it "updates the lockfile successfully" do
          expect(updated_files.map(&:name)).to eq(%w(poetry.lock))

          updated_lockfile = updated_files.find { |f| f.name == "poetry.lock" }

          lockfile_obj = TomlRB.parse(updated_lockfile.content)
          certifi = lockfile_obj["package"].find { |d| d["name"] == "certifi" }

          expect(certifi["version"]).to eq("2018.11.29")

          expect(lockfile_obj["metadata"]["content-hash"]).
            to start_with("8cea4ecb5b2230fbd4a33a67a4da004f1ccabad48352aaf040a")
        end
      end
    end
  end

  describe "#prepared_project_file" do
    subject(:prepared_project) { updater.send(:prepared_pyproject) }

    context "with a python_index with auth details" do
      let(:pyproject_fixture_name) { "private_secondary_source.toml" }
      let(:lockfile_fixture_name) { "private_secondary_source.lock" }
      let(:dependency_name) { "luigi" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "2.8.9",
          previous_version: "2.8.8",
          package_manager: "pip",
          requirements: [{
            requirement: "2.8.9",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "2.8.8",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end
      let(:credentials) do
        [{
          "type" => "python_index",
          "index-url" => "https://some.internal.registry.com/pypi/",
          "username" => "test",
          "password" => "test"
        }]
      end

      it "prepares a pyproject file without credentials in" do
        repo_obj = TomlRB.parse(prepared_project, symbolize_keys: true)[:tool][:poetry][:source]
        expect(repo_obj[0][:url]).to eq(credentials[0]["index-url"])

        user_pass = "#{credentials[0]['user']}:#{credentials[0]['password']}@"
        expect(repo_obj[0][:url]).to_not include(user_pass)
      end
    end
  end
end
