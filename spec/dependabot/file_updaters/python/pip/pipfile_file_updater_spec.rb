# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pip/pipfile_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::FileUpdaters::Python::Pip::PipfileFileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:dependency_files) { [pipfile, lockfile] }
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("python", "pipfiles", pipfile_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile.lock",
      content: fixture("python", "lockfiles", lockfile_fixture_name)
    )
  end
  let(:pipfile_fixture_name) { "version_not_specified" }
  let(:lockfile_fixture_name) { "version_not_specified.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.18.4",
      previous_version: "2.18.0",
      package_manager: "pip",
      requirements: [{
        requirement: "*",
        file: "Pipfile",
        source: nil,
        groups: ["default"]
      }],
      previous_requirements: [{
        requirement: "*",
        file: "Pipfile",
        source: nil,
        groups: ["default"]
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

    context "with a capital letter" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end
      let(:pipfile_fixture_name) { "hard_names" }
      let(:lockfile_fixture_name) { "hard_names.lock" }

      it "updates the lockfile successfully (and doesn't affect other deps)" do
        expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

        updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
        json_lockfile = JSON.parse(updated_lockfile.content)

        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).
          to eq("==3.4.0")
      end
    end

    context "when the Pipfile hasn't changed" do
      let(:pipfile_fixture_name) { "version_not_specified" }
      let(:lockfile_fixture_name) { "version_not_specified.lock" }

      it "only returns the lockfile" do
        expect(updated_files.map(&:name)).to eq(["Pipfile.lock"])
      end
    end

    context "when the Pipfile specified a Python version" do
      let(:pipfile_fixture_name) { "required_python" }
      let(:lockfile_fixture_name) { "required_python.lock" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it "updates both files correctly" do
        expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

        updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
        updated_pipfile = updated_files.find { |f| f.name == "Pipfile" }
        json_lockfile = JSON.parse(updated_lockfile.content)

        expect(updated_pipfile.content).
          to include('python_full_version = "2.7.15"')
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.4.0")
        expect(json_lockfile["_meta"]["requires"]).
          to eq(JSON.parse(lockfile.content)["_meta"]["requires"])
        expect(json_lockfile["develop"]["funcsigs"]["markers"]).
          to eq("python_version < '3.0'")
      end
    end

    context "when the Pipfile included an environment variable source" do
      let(:pipfile_fixture_name) { "environment_variable_source" }
      let(:lockfile_fixture_name) { "environment_variable_source.lock" }
      let(:credentials) do
        [
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          },
          {
            "type" => "python_index",
            "index-url" => "https://pypi.python.org/simple"
          }
        ]
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it "updates both files correctly" do
        expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

        updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
        updated_pipfile = updated_files.find { |f| f.name == "Pipfile" }
        json_lockfile = JSON.parse(updated_lockfile.content)

        expect(updated_pipfile.content).
          to include("pypi.python.org/${ENV_VAR}")
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["_meta"]["sources"]).
          to eq([{ "url" => "https://pypi.python.org/${ENV_VAR}",
                   "verify_ssl" => true }])
        expect(updated_lockfile.content).
          to_not include("pypi.python.org/simple")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.4.0")
      end
    end

    describe "the updated Pipfile.lock" do
      let(:updated_lockfile) do
        updated_files.find { |f| f.name == "Pipfile.lock" }
      end

      let(:json_lockfile) { JSON.parse(updated_lockfile.content) }

      it "updates only what it needs to" do
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.2.3")
        expect(json_lockfile["_meta"]["hash"]).
          to eq(JSON.parse(lockfile.content)["_meta"]["hash"])
      end

      describe "with a subdependency from an extra" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "raven",
            version: "6.7.0",
            previous_version: "5.27.1",
            package_manager: "pip",
            requirements: [{
              requirement: "==6.7.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }],
            previous_requirements: [{
              requirement: "==5.27.1",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          )
        end
        let(:pipfile_fixture_name) { "extra_subdependency" }
        let(:lockfile_fixture_name) { "extra_subdependency.lock" }

        it "doesn't remove the subdependency" do
          expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

          updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
          json_lockfile = JSON.parse(updated_lockfile.content)

          expect(json_lockfile["default"]["raven"]["version"]).
            to eq("==6.7.0")
          expect(json_lockfile["default"]["blinker"]["version"]).
            to eq("==1.4")
        end
      end
    end
  end

  describe "#updated_pipfile_content" do
    subject(:updated_pipfile_content) { updater.send(:updated_pipfile_content) }

    let(:pipfile_fixture_name) { "version_not_specified" }
    let(:lockfile_fixture_name) { "version_not_specified.lock" }

    context "with single quotes" do
      let(:pipfile_fixture_name) { "with_quotes" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "python-decouple",
          version: "3.2",
          previous_version: "3.1",
          package_manager: "pip",
          requirements: [{
            requirement: "==3.2",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==3.1",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it { is_expected.to include(%q('python_decouple' = "==3.2")) }
    end

    context "with double quotes" do
      let(:pipfile_fixture_name) { "with_quotes" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it { is_expected.to include('"requests" = "==2.18.4"') }
    end

    context "without quotes" do
      let(:pipfile_fixture_name) { "with_quotes" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "pytest",
          version: "3.3.1",
          previous_version: "3.2.3",
          package_manager: "pip",
          requirements: [{
            requirement: "==3.3.1",
            file: "Pipfile",
            source: nil,
            groups: ["develop"]
          }],
          previous_requirements: [{
            requirement: "==3.2.3",
            file: "Pipfile",
            source: nil,
            groups: ["develop"]
          }]
        )
      end

      it { is_expected.to include(%(\npytest = "==3.3.1"\n)) }
      it { is_expected.to include(%(\npytest-extension = "==3.2.3"\n)) }
      it { is_expected.to include(%(\nextension-pytest = "==3.2.3"\n)) }
    end

    context "with a capital letter" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end
      let(:pipfile_fixture_name) { "hard_names" }
      let(:lockfile_fixture_name) { "hard_names.lock" }

      it { is_expected.to include('Requests = "==2.18.4"') }
    end
  end
end
