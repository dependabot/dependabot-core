# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pip"
require "dependabot/shared_helpers"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Python::Pip do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:dependency_files) { [requirements] }
  let(:requirements) do
    Dependabot::DependencyFile.new(
      content: fixture("python", "requirements", requirements_fixture_name),
      name: "requirements.txt"
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "psycopg2",
      version: "2.8.1",
      requirements: [{
        file: "requirements.txt",
        requirement: "==2.8.1",
        groups: [],
        source: nil
      }],
      previous_requirements: [{
        file: "requirements.txt",
        requirement: "==2.7.1",
        groups: [],
        source: nil
      }],
      package_manager: "pip"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    context "with a Pipfile and Pipfile.lock" do
      let(:dependency_files) { [pipfile, lockfile] }
      let(:pipfile) do
        Dependabot::DependencyFile.new(
          name: "Pipfile",
          content: fixture("python", "pipfiles", "version_not_specified")
        )
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "Pipfile.lock",
          content: fixture("python", "lockfiles", "version_not_specified.lock")
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
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

      it "delegates to PipfileFileUpdater" do
        expect(described_class::PipfileFileUpdater).
          to receive(:new).and_call_original
        expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      end
    end

    context "with a pyproject.toml and pyproject.lock" do
      let(:dependency_files) { [pyproject, lockfile] }
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content:
            fixture("python", "pyproject_files", "version_not_specified.toml")
        )
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "pyproject.lock",
          content:
            fixture("python", "pyproject_locks", "version_not_specified.lock")
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "*",
            file: "pyproject.toml",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "*",
            file: "pyproject.toml",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it "delegates to PoetryFileUpdater" do
        expect(described_class::PoetryFileUpdater).
          to receive(:new).and_call_original
        expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      end
    end

    context "with a pip-compile file" do
      let(:dependency_files) { [manifest_file, generated_file] }
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test.in",
          content: fixture("python", "pip_compile_files", "unpinned.in")
        )
      end
      let(:generated_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test.txt",
          content: fixture("python", "requirements", "pip_compile_unpinned.txt")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "psycopg2",
          version: "2.8.1",
          requirements: [{
            file: "requirements/test.in",
            requirement: "==2.8.1",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "requirements/test.in",
            requirement: "==2.7.1",
            groups: [],
            source: nil
          }],
          package_manager: "pip"
        )
      end

      it "delegates to PipCompileFileUpdater" do
        dummy_updater =
          instance_double(described_class::PipCompileFileUpdater)
        allow(described_class::PipCompileFileUpdater).to receive(:new).
          and_return(dummy_updater)
        expect(dummy_updater).
          to receive(:updated_dependency_files).
          and_return([OpenStruct.new(name: "updated files")])
        expect(updater.updated_dependency_files).
          to eq([OpenStruct.new(name: "updated files")])
      end
    end

    describe "with no Pipfile or pip-compile files" do
      let(:dependency_files) { [requirements] }

      it "delegates to RequirementFileUpdater" do
        expect(described_class::RequirementFileUpdater).
          to receive(:new).and_call_original
        expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      end
    end
  end
end
